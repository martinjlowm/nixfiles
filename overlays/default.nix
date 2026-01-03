# Overlays for customizing packages
{
  # Main overlay for package customizations
  default = final: prev: {
    vorbis-tools = prev.vorbis-tools.overrideAttrs (old: {
      postPatch = null;
    });
  };
}
