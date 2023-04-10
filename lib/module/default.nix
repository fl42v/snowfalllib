{ core-inputs
, user-inputs
, snowfall-lib
}:

let
  inherit (builtins) baseNameOf;
  inherit (core-inputs.nixpkgs.lib) assertMsg foldl mapAttrs hasPrefix;

  user-modules-root = snowfall-lib.fs.get-snowfall-file "modules";
in
{
  module = {
    # Create flake output modules.
    # Type: Attrs -> Attrs
    # Usage: create-modules { src = ./my-modules; overrides = { inherit another-module; }; alias = { default = "another-module" }; }
    #   result: { another-module = ...; my-module = ...; default = ...; }
    create-modules =
      { src ? "${user-modules-root}/nixos"
      , overrides ? { }
      , alias ? { }
      }:
      let
        user-modules = snowfall-lib.fs.get-default-nix-files-recursive src;
        create-module-metadata = module: {
          name =
            let
              path-name = builtins.replaceStrings [ src "/default.nix" ] [ "" "" ] (builtins.unsafeDiscardStringContext module);
            in
            if hasPrefix "/" path-name then
              builtins.substring 1 ((builtins.stringLength path-name) - 1) path-name
            else
              path-name;
          path = module;
        };
        modules-metadata = builtins.map create-module-metadata user-modules;
        merge-modules = modules: metadata:
          modules // {
            # @NOTE(jakehamilton): home-manager *requires* modules to specify named arguments or it will not
            # pass values in. For this reason we must specify things like `pkgs` as a named attribute.
            ${metadata.name} = args@{ pkgs, ... }:
              let
                system = args.system or args.pkgs.system;
                target = args.target or system;

                format =
                  let
                    virtual-system-type = snowfall-lib.system.get-virtual-system-type target;
                  in
                  if virtual-system-type != "" then
                    virtual-system-type
                  else if snowfall-lib.system.is-darwin target then
                    "darwin"
                  else
                    "linux";

                # Replicates the specialArgs from Snowfall Lib's system builder.
                modified-args = args // {
                  inherit system target format;
                  virtual = args.virtual or (snowfall-lib.system.get-virtual-system-type target != "");
                  systems = args.systems or { };


                  lib = snowfall-lib.internal.system-lib;
                  pkgs = user-inputs.self.pkgs.${system}.nixpkgs;

                  inputs = snowfall-lib.flake.without-src user-inputs;
                };
                user-module = import metadata.path modified-args;
              in
              user-module // { _file = metadata.path; };
          };
        modules-without-aliases = foldl merge-modules { } modules-metadata;
        aliased-modules = mapAttrs (name: value: modules-without-aliases.${value}) alias;
        modules = modules-without-aliases // aliased-modules // overrides;
      in
      modules;
  };
}
