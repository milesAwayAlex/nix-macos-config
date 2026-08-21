# Local filtering resolver: dnsmasq :53 -> blocky :5300 -> unbound :5335 (D21).
#
# dnsmasq is a pure forwarder and exists only because blocky cannot bind port
# 53 here: mDNSResponder holds *:53, and taking a more specific address over a
# wildcard bind needs SO_REUSEADDR on the second socket, which blocky's
# listener does not set. The front goes away if that ever lands upstream.
#
# The tunnel outranks all of this by design — Harmony writes DNS into the
# dynamic SystemConfiguration store, which masks what `networksetup` writes,
# so filtering applies exactly when the tunnel is down (D21).
{ lib, pkgs, ... }:
let
  blockyPort = 5300;
  unboundPort = 5335;

  hagezi =
    name: "https://codeberg.org/hagezi/mirror2/raw/branch/main/dns-blocklists/wildcard/${name}.txt";

  # A source containing a newline is inline text to blocky and one starting
  # with `http` is a download, so a bare store path is read as a file.
  firefoxCanary = pkgs.writeText "firefox-canary.txt" ''
    use-application-dns.net
  '';

  # pro.plus wildcards the zones pro leaves alone — doubleclick.net above all,
  # which is why pro alone changed little. It also wildcards
  # googletagmanager.com, which hagezi keep out of pro because blocking that
  # zone breaks consent banners and some in-page behaviour. Allowed back so
  # the doubleclick win does not come with that tail.
  # Wildcard form: a bare domain here matches only itself, and sites load
  # gtm.js from www.
  allowGtm = pkgs.writeText "allow-gtm.txt" ''
    *.googletagmanager.com
  '';

  blockyConfig = (pkgs.formats.yaml { }).generate "blocky.yml" {
    ports = {
      dns = "127.0.0.1:${toString blockyPort}";
      # The API is how blocky is operated: `blocky blocking disable 10m` when a
      # list breaks a site, `blocky lists refresh`, `blocky blocking status`.
      http = "127.0.0.1:4000";
    };

    upstreams = {
      # strict, so unbound answers and Quad9 is reached only when it cannot —
      # a network dropping outbound 53 is the case this covers. The default
      # parallel_best races them and would send every query to both.
      strategy = "strict";
      groups.default = [
        "127.0.0.1:${toString unboundPort}"
        "tcp-tls:dns.quad9.net:853"
      ];
      # Generous, because the first upstream does real recursion from cold.
      timeout = "5s";
    };

    # There is no Happy Eyeballs fallback: an AAAA answer for codeberg.org
    # means the download fails five times and blocking silently never engages.
    connectIPVersion = "v4";

    # Resolving the DoT hostname cannot go through the group being defined.
    bootstrapDns = [
      {
        upstream = "tcp-tls:dns.quad9.net";
        ips = [ "9.9.9.9" ];
      }
    ];

    blocking = {
      blockType = "nxDomain";
      loading = {
        # Serve immediately and load lists in the background; the alternative
        # blocks startup on a 2.1M-entry download.
        strategy = "fast";
        refreshPeriod = "4h";
        downloads = {
          timeout = "300s";
          attempts = 5;
          cooldown = "5s";
        };
        concurrency = 1;
      };
      denylists = {
        pro = [ (hagezi "pro.plus") ];
        tif = [ (hagezi "tif.medium") ];
        # NXDOMAIN here is Firefox's signal to leave DoH off, so it resolves
        # through this stack instead of around it.
        firefox-canary = [ "${firefoxCanary}" ];
      };
      allowlists.pro = [ "${allowGtm}" ];
      clientGroupsBlock.default = [
        "pro"
        "tif"
        "firefox-canary"
      ];
    };

    # blocky owns caching; the dnsmasq front is a pure shim.
    caching.prefetching = false;

    # Default is console, which at this log level writes every domain the
    # machine resolves into an unrotated file under /var/log.
    queryLog.type = "none";
  };

  # Not YAML: repeated keys like private-address are part of the format.
  unboundConfig = pkgs.writeText "unbound.conf" ''
    server:
      interface: 127.0.0.1@${toString unboundPort}
      access-control: 127.0.0.1/32 allow
      # launchd supervises, so no forking, no chroot and no pidfile. Dropping
      # to nobody is safe because nothing here needs a writable path.
      do-daemonize: no
      chroot: ""
      username: "nobody"
      directory: "/"
      pidfile: ""
      logfile: ""
      use-syslog: no
      verbosity: 1
      hide-identity: yes
      hide-version: yes
      prefetch: yes
      qname-minimisation: yes
      harden-glue: yes
      harden-dnssec-stripped: yes
      aggressive-nsec: yes
      # Pinned by the flake, so there is no RFC 5011 rollover state to keep
      # writable — a KSK roll arrives as a dns-root-data bump.
      trust-anchor-file: "${pkgs.dns-root-data}/root.key"
      root-hints: "${pkgs.dns-root-data}/root.hints"
      # Rebind protection: a public answer may not point into private space.
      private-address: 10.0.0.0/8
      private-address: 172.16.0.0/12
      private-address: 192.168.0.0/16
      private-address: 169.254.0.0/16
      private-address: fd00::/8
      private-address: fe80::/10
  '';

  keepAlive = {
    KeepAlive = true;
    RunAtLoad = true;
  };
in
{
  # Port 53 needs root, so these are daemons rather than the user agents redis
  # uses. launchd has no ordering primitive; the stack tolerates that because
  # blocky's startVerifyUpstream defaults off and KeepAlive retries.
  launchd.daemons = {
    dnsmasq = {
      # --no-resolv is load-bearing: without it dnsmasq adds the resolvers
      # from /etc/resolv.conf as peers of --server and balances across them,
      # so a share of queries would skip blocky entirely.
      command = lib.concatStringsSep " " [
        "${pkgs.dnsmasq}/bin/dnsmasq"
        "--keep-in-foreground"
        "--listen-address=127.0.0.1"
        "--port=53"
        "--no-resolv"
        "--no-hosts"
        "--cache-size=0"
        "--server=127.0.0.1#${toString blockyPort}"
      ];
      serviceConfig = keepAlive // {
        StandardOutPath = "/var/log/dnsmasq.log";
        StandardErrorPath = "/var/log/dnsmasq.log";
      };
    };

    blocky = {
      command = "${pkgs.blocky}/bin/blocky --config ${blockyConfig}";
      serviceConfig = keepAlive // {
        StandardOutPath = "/var/log/blocky.log";
        StandardErrorPath = "/var/log/blocky.log";
      };
    };

    unbound = {
      command = "${pkgs.unbound}/bin/unbound -c ${unboundConfig}";
      serviceConfig = keepAlive // {
        StandardOutPath = "/var/log/unbound.log";
        StandardErrorPath = "/var/log/unbound.log";
      };
    };
  };

  # An activation script over `networksetup -setdnsservers`, each service
  # guarded by a case against `-listallnetworkservices`, so naming one this
  # machine lacks is skipped rather than fatal. Convergent, unlike
  # system.defaults. `networking.search` stays unset: the module would pass
  # the literal `empty`, which hands search domains back to DHCP.
  networking.dns = [ "127.0.0.1" ];
  networking.knownNetworkServices = [
    "Wi-Fi"
    "Ethernet"
    "Thunderbolt Bridge"
    "Thunderbolt Ethernet"
    "USB 10/100/1000 LAN"
    "USB 10/100/1G/2.5G LAN"
  ];
}
