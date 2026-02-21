{ config, pkgs, ... }:

let
  commonPkgs = import ./common-packages.nix { inherit pkgs; };
in

{
  # Основная информация
  home.username = "cosmdandy";
  home.homeDirectory = "/home/cosmdandy";
  home.stateVersion = "24.05";

  # Пакеты из общего списка
  home.packages = commonPkgs;

  # Включение Home Manager
  programs.home-manager.enable = true;

  # Настройка окружения
  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
