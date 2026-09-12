# Postgres for local development, run as a launchd user agent with KeepAlive —
# the shape Postgres.app had, minus the menu bar (D24). Version 16 because the
# data is 16; PostGIS and pgvector because the work databases contain both
# (the other extensions they use — pg_trgm, uuid-ossp, pgcrypto — ship with
# postgres itself).
#
# nix-darwin's module defaults are set for a Linux daemon and need the same
# fixes redis did: the package (postgresql 14) and the data directory
# (/var/lib, unwritable for the primary user the agent runs as), plus the
# three explained inline.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.system.primaryUser;
  cfg = config.services.postgresql;
  # Versioned like nix-darwin's own default, because the on-disk format is
  # the major version: bumping `package` starts an empty 17 beside the 16
  # instead of refusing to start on it, and pg_upgrade moves the data across.
  # No spaces in this path — the module interpolates it unquoted, which is
  # why Postgres.app's `Application Support` directory could not be adopted
  # where it was.
  dataDir = "${config.users.users.${user}.home}/.local/share/postgresql/${cfg.package.psqlSchema}";
in
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    extraPlugins = [
      cfg.package.pkgs.postgis
      cfg.package.pkgs.pgvector
    ];
    inherit dataDir;

    # Loopback only (the module's default) and no passwords on it: the work
    # code connects with defaults, as it did to Postgres.app.
    authentication = lib.mkForce ''
      local all all              trust
      host  all all 127.0.0.1/32 trust
      host  all all ::1/128      trust
    '';

    # initdb derives this from the locale, but the module regenerates
    # postgresql.conf from `settings` alone — left out, to_tsvector(text)
    # silently switches to the `simple` dictionary.
    settings.default_text_search_config = "pg_catalog.english";

    # A fresh cluster collates like the adopted one and like Cloud SQL. Under
    # launchd initdb sees no locale and would pick C.
    initdbArgs = [ "--locale=en_US.UTF-8" ];

    # Upstream's prefix; the module drops the timestamp on the assumption
    # that a journal adds one, and a log file does not.
    logLinePrefix = "%m [%p] ";
  };

  # The server logs to stderr and launchd gives an agent nowhere to put it,
  # so without this a refused start would be silent. Same file Postgres.app
  # kept.
  launchd.user.agents.postgresql.serviceConfig.StandardErrorPath = "${dataDir}/postgresql.log";

  system.activationScripts.postActivation.text = ''
    install -d -o ${user} -g staff -m 700 ${dataDir}
  '';
}
