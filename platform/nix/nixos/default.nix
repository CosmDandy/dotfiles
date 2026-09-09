# NixOS stand: the same user environment as the Linux containers, but with the system
# layer declared too. On Ubuntu that layer is `platform/linux/install.sh` plus an apt
# minimum (zsh git xz-utils curl); here it is this file, and the apt minimum has no
# counterpart at all — nix is the system.
{
  lib,
  pkgs,
  options,
  modulesPath,
  user,
  hostname,
  ...
}:
let
  # The owner's personal key, the same one Proxmox cloud-init hands to the VMs.
  # NOTE: public half only, and deliberately in the public repo — it is what makes the
  # stand reachable after disko has wiped cloud-init's copy off the disk.
  ownerKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIrGaPmqicysKoalLIq7Y6gMGX3n2vImMwCzwhTO+hM2 i@cosmdandy.dev personal file 2026-08";
  homeDir = "/home/${user}";
in
{
  imports = [
    # virtio drivers in the initrd, no fsck on the root, ttyS0 wired up
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk.nix
  ];

  # --- boot ---------------------------------------------------------------------

  boot.loader.grub = {
    enable = true;
    # NOTE: `devices` is NOT set here — disko derives it from the EF02 partition in
    # disk.nix, and setting it again fails the build with "duplicated devices in
    # mirroredBoots".
    # NOTE: the GRUB menu on the serial line, not only the kernel. Proxmox gives this
    # VM `serial0: socket` and `vga: serial0`, so `qm terminal 9002` is the ONLY way
    # in once sshd or the network is broken — and a bootloader that talks to a VGA
    # console nobody can see makes a failed generation unrollbackable.
    extraConfig = ''
      serial --unit=0 --speed=115200
      terminal_input serial
      terminal_output serial
    '';
  };
  # tty0 first, ttyS0 last: the LAST console= is the one that gets /dev/console.
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200n8"
  ];

  services.qemuGuest.enable = true; # `qm guest cmd … network-get-interfaces`

  # --- system -------------------------------------------------------------------

  networking.hostName = hostname;
  networking.useDHCP = lib.mkDefault true; # 192.168.20.0/24 has a DHCP server
  # NOTE: without this the address MOVES. dhcpcd identifies itself by a generated DUID,
  # Ubuntu's netplan asked by MAC — so the same VM got a second lease the moment it
  # stopped being Ubuntu (.206 → .209, mid-install, with nixos-anywhere still polling
  # the old address). `clientid` puts the MAC back in the request.
  networking.dhcpcd.extraConfig = "clientid";

  time.timeZone = "Europe/Moscow";
  i18n.defaultLocale = "en_US.UTF-8";

  # terraform (BUSL) is in the devops profile; useGlobalPkgs means home-manager gets
  # its pkgs from here, so the flag has to be set at the system level.
  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # a switch from the user account has to be able to write to the store
    trusted-users = [
      "root"
      user
    ];
  };
  # NOTE: the stand rebuilds the whole devops profile over and over on 64 GiB. Without
  # this the old generations' closures alone fill the disk in a few days.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # NOTE: mason and Claude Code install PREBUILT binaries that expect a
  # /lib64/ld-linux-x86-64.so.2 NixOS does not have. This is the one thing an
  # ubuntu host gets for free and a NixOS host does not.
  programs.nix-ld = {
    enable = true;
    # NOTE: `.default ++`, not a plain list — assigning `libraries` REPLACES the
    # module's default set (zlib, openssl, stdenv.cc.cc …), which is what makes
    # lua-language-server, stylua, hadolint and tflint run at all.
    # NOTE: icu is the one addition. mason's marksman is a .NET binary and dies with
    # "Couldn't find a valid ICU package installed on the system" — on Ubuntu libicu
    # comes with the base image, here nothing pulls it in.
    libraries = options.programs.nix-ld.libraries.default ++ [ pkgs.icu ];
  };

  # The login shell comes from the SYSTEM closure, exactly as on Ubuntu — a broken or
  # not-yet-built user profile must never lock the account out.
  programs.zsh.enable = true;
  users.users.${user} = {
    isNormalUser = true;
    home = homeDir;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [ ownerKey ];
  };
  # Key-only ssh and no password on the account, so sudo has no password to ask for.
  security.sudo.wheelNeedsPassword = false;

  users.users.root.openssh.authorizedKeys.keys = [ ownerKey ];
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password"; # nixos-rebuild --target-host root@…
    };
  };

  # Everything a user actually types comes from home.packages (platform/nix/home).
  # Only what the system itself needs lives here.
  environment.systemPackages = with pkgs; [
    git # the clone unit below, and submodule updates by hand
    curl
    vim # a fallback editor for the generation where neovim did not build
  ];

  # --- the working copy ----------------------------------------------------------

  # NOTE: home/files.nix symlinks every dotfile to ~/dotfiles/…, so the clone must
  # exist BEFORE home-manager activates or the whole home is dangling symlinks and
  # the nvim/mason hooks skip themselves (they guard on ~/.config/nvim/init.lua).
  # On Ubuntu the user clones by hand and then runs install.sh; here there is no
  # install.sh, so the system does it.
  # NOTE: https, not ssh — the stand holds no key to github. The `private` and
  # `tools/claude/custom` submodules therefore stay uninitialised until someone
  # forwards an agent in and runs `git submodule update --init`.
  systemd.services.dotfiles-clone = {
    description = "Working copy of the dotfiles repo for ${user}";
    wantedBy = [ "multi-user.target" ];
    before = [ "home-manager-${user}.service" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.git ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = user;
      Group = "users";
    };
    script = ''
      test -d ${homeDir}/dotfiles/.git && exit 0
      git clone https://github.com/CosmDandy/dotfiles.git ${homeDir}/dotfiles
    '';
  };

  # NOTE: kept at the release the user environment was written against
  # (home/default.nix pins the same value), NOT bumped to the current nixpkgs — the
  # option exists precisely so stateful defaults do not move under a running host.
  system.stateVersion = "26.05";
}
