# Disk layout of the Proxmox stand, applied by disko during `nixos-anywhere`.
#
# NOTE: the VM boots SeaBIOS, not UEFI — `qm config` carries no `bios: ovmf` and no
# efidisk0, and /sys/firmware/efi does not exist inside the guest. So GRUB goes into a
# 1 MiB BIOS-boot partition (EF02) and there is deliberately NO ESP: an ESP here would
# be dead weight that nothing ever mounts.
# NOTE: the priorities are explicit because disko otherwise lays partitions out in
# attribute order, and `root` sorts before `swap` — root would swallow the whole disk
# with `size = "100%"` and leave nothing for swap.
{
  disko.devices.disk.main = {
    # virtio-scsi-single, the only disk the VM has
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          priority = 1;
          size = "1M";
          type = "EF02";
        };
        # NOTE: swap is not optional here — a switch of the devops profile compiles
        # ~40 treesitter parsers and mason's C modules, and the same 16 GiB has to
        # hold the build while the kexec installer keeps its whole store in RAM.
        swap = {
          priority = 2;
          size = "8G";
          content.type = "swap";
        };
        root = {
          priority = 3;
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
