# Overlays for customizing packages
{
  # Main overlay for package customizations
  default = final: prev: {
    vorbis-tools = prev.vorbis-tools.overrideAttrs (old: {
      postPatch = null;
    });

    whatsapp-for-mac = prev.whatsapp-for-mac.overrideAttrs (old: {
      version = "2.26.9.17";

      src = prev.fetchzip {
        extension = "zip";
        name = "WhatsApp.app";
        url = "https://web.whatsapp.com/desktop/mac_native/release/?version=2.26.9.17&extension=zip&configuration=Release&branch=master";
        hash = "sha256-bba22HBnIeio4M92mckiOa1IQpRUfx/I7OkfA4hO6rU=";
      };
    });
  };
}
