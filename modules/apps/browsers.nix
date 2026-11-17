/*
  One browser: `ungoogled-chromium`, the Chromium engine without the Google service
  integration. The trade-offs are real and documented in the README (no Widevine, so no
  DRM streaming; no Google account sync).

  Firefox was here too, disabled by policy and pointed at a blank page, and nothing used
  it. Two browser engines in an appliance image is two things to update, two closures to
  measure and a choice nobody asked for.
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
