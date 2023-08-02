# Tailscale on the USG Pro 4

This repo contains a single script that can be used to install and run a [Tailscale](https://tailscale.com/) instance on your [USG Pro 4](https://store.ui.com/us/en/products/unifi-security-gateway-pro). The [tailscale-udm](https://github.com/SierraSoftworks/tailscale-udm) project is an excellent way to install and manage Tailscale on the Unifi Dream Machine, but it doesn't work with the USG Pro 4. The script in this repo is basically a copied and slightly modified version of `tailscale-udm`.

## Installation

1. Download the script
  ```
  curl -sSLq https://raw.githubusercontent.com/wtcross/tailscale-usg/main/tailscale-usg.sh -o /config/tailscale-usg.sh
  ```

2. Install
  ```
  sh /config/tailscale-usg.sh install
  ```