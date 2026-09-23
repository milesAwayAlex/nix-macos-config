# Two VM-backed builds for comparing real KVM with forced TCG on the builder.
# `attempt` must change between runs so successful outputs cannot hide a failure.
{
  pkgs,
  accel ? "kvm",
  attempt,
}:
assert builtins.elem accel [
  "kvm"
  "tcg"
];
let
  qemu = pkgs.writeShellScript "devvm-probe-qemu" ''
    args=("$@")
    for i in "''${!args[@]}"; do
      args[$i]="''${args[$i]//loglevel=4/loglevel=7 earlycon}"
    done
    # Capture serial output separately: CRLF output through the remote Nix
    # logger can lose the text and leave blank lines, hiding kernel faults.
    ${pkgs.coreutils}/bin/timeout --kill-after=5 120 \
      ${pkgs.qemu_kvm}/bin/qemu-system-aarch64 \
      -machine virt,gic-version=max,accel=${accel} -cpu max \
      -serial file:serial.log "''${args[@]}"
    status=$?
    ${pkgs.coreutils}/bin/tr -d '\r' < serial.log
    exit "$status"
  '';
  vm = pkgs.vmTools.override { customQemu = qemu; };
in
map
  (
    slot:
    vm.runInLinuxVM (
      pkgs.runCommand "devvm-${accel}-${slot}-${attempt}"
        {
          memSize = 1024;
          enableParallelBuilding = false;
          QEMU_OPTS = "-smp 6";
          nativeBuildInputs = [ pkgs.e2fsprogs ];
          preVM = ''
            ${pkgs.lib.optionalString (accel == "kvm") ''
              if [ ! -c /dev/kvm ]; then
                echo "KVM probe requires /dev/kvm: enable nesting and restart devvm first." >&2
                exit 1
              fi
            ''}
            echo "Starting ${accel} VM ${slot}"
            date -Ins
          '';
          postVM = ''
            echo "Finished ${accel} VM ${slot}"
            date -Ins
          '';
        }
        ''
          uname -a
          truncate -s 256M /tmp/probe.img
          mkfs.ext4 -F /tmp/probe.img
          dd if=/dev/zero of=/tmp/payload bs=1M count=64 status=none
          sha256sum /tmp/payload
          echo success > "$out"
        ''
    )
  )
  [
    "a"
    "b"
  ]
