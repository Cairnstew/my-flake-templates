# nixos/configuration.nix
{ pkgs, ... }: {
  # Your NixOS config here
  users.users.user = {
    isNormalUser = true;
    extraGroups  = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-rsa ...your public key here..."
    ];
    shell = pkgs.bashInteractive;
  };

  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [ vim curl ];

  system.stateVersion = "24.11";
}