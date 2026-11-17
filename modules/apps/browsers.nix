/*
  One browser: `ungoogled-chromium`, Chromium without the Google service integration. The
  trade-offs are in the README (no Widevine, so no DRM streaming; no account sync). One
  engine: a second is a second closure to update and a choice nobody asked for.
*/
{
  pkgs,
  ...
}:
{
  environment.systemPackages = with pkgs; [
    ungoogled-chromium
  ];
}
