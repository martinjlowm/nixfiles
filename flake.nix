{
  description = "NixOS and nix-darwin configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nextNixpkgsDevenv.url = "github:NixOS/nixpkgs/e99366c665bdd53b7b500ccdc5226675cfc51f45";
    nextNixpkgs.url = "github:NixOS/nixpkgs/d1c2cd5033acedf3f29affd8d44e288107e95238";
    nextNixpkgsClaude.url = "github:NixOS/nixpkgs/5ee9f0ecf9ea4ef788544118d184a5d37baf5eee";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-rosetta-builder.url = "github:cpick/nix-rosetta-builder";
    nix-rosetta-builder.inputs.nixpkgs.follows = "nixpkgs";

    onepassword-secrets.url = "github:brizzbuzz/opnix";
    onepassword-secrets.inputs.nixpkgs.follows = "nixpkgs";

    # Factbird's shared Claude Code skills. Skill folders only, no flake.
    agent-skills.url = "git+https://github.com/FactbirdHQ/agent-skills?ref=main";
    agent-skills.flake = false;

    # HumanLayer's skills, for `show-me`. Skill folders only, no flake.
    humanlayer-skills.url = "git+https://github.com/humanlayer/skills?ref=main";
    humanlayer-skills.flake = false;

    # Matt Pocock's skills, for `retro` and the `writing-for-agents` guide it
    # loads. Skill folders only, no flake.
    mattpocock-skills.url = "git+https://github.com/mattpocock/skills?ref=main";
    mattpocock-skills.flake = false;

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {
    self,
    nix-darwin,
    home-manager,
    nixpkgs,
    nextNixpkgsDevenv,
    nextNixpkgsClaude,
    nextNixpkgs,
    nix-rosetta-builder,
    onepassword-secrets,
    agent-skills,
    humanlayer-skills,
    mattpocock-skills,
    treefmt-nix,
  }: let
    # Import overlays
    overlays = import ./overlays;

    # Import helper functions
    lib = import ./lib {inherit inputs overlays;};

    # ──────────────────────────────────────────────────────────────
    # Darwin (macOS) Configurations
    # ──────────────────────────────────────────────────────────────

    # wololobook - MacBook Pro (Apple Silicon)
    wololobook = lib.mkDarwinSystem {
      system = "aarch64-darwin";
      hostname = "wololobook";
      username = "martinjlowm";
      modules = [
        ./hosts/darwin/wololobook
        {
          system.configurationRevision = self.rev or self.dirtyRev or null;
        }
      ];
    };
    # ──────────────────────────────────────────────────────────────
    # NixOS (Linux) Configurations
    # ──────────────────────────────────────────────────────────────
    # Example NixOS configuration (uncomment and customize when needed)
    # example-nixos = lib.mkNixosSystem {
    #   system = "x86_64-linux";
    #   hostname = "example-nixos";
    #   username = "martinjlowm";
    #   modules = [
    #     ./hosts/nixos/example
    #   ];
    # };
  in {
    # Darwin configurations
    darwinConfigurations = {
      "wololobook" = wololobook;
      "Martins-MacBook-Pro" = wololobook; # Alias for the same machine
    };

    # NixOS configurations (add your Linux machines here)
    nixosConfigurations = {
      # "example-nixos" = example-nixos;
    };

    # Expose packages for convenience
    darwinPackages = wololobook.pkgs;

    # Script packages
    packages = let
      systems = ["aarch64-darwin" "x86_64-linux" "x86_64-darwin" "aarch64-linux"];
      scriptNames = ["agent-mono-items" "dependabot" "fix" "git-bug-hotspots" "git-commit-velocity" "git-contributor-rankings" "git-firefighting" "git-most-changed" "git-recent-contributors" "github-issues" "github-project" "loop" "playwright-at" "pr-maintenance" "pr-review" "project" "rmtree" "tech-spec" "worktree"];
    in
      builtins.listToAttrs (map (system: {
          name = system;
          value = let
            pkgs = lib.mkPkgs {inherit system;};
            scripts = pkgs.callPackage ./scripts {};
          in
            nixpkgs.lib.getAttrs scriptNames scripts
            // {
              claude-code = pkgs.claude-code;
              gh-image = pkgs.gh-image;
              gh-with-image = pkgs.gh-with-image;
              gh-axi = pkgs.gh-axi;
            };
        })
        systems);

    # `nix develop <nixfiles>#gh-image`: gh with the gh-image extension embedded.
    devShells = let
      systems = ["aarch64-darwin" "x86_64-linux" "x86_64-darwin" "aarch64-linux"];
    in
      builtins.listToAttrs (map (system: {
          name = system;
          value = let
            pkgs = lib.mkPkgs {inherit system;};
          in rec {
            gh-image = pkgs.mkShell {
              packages = [pkgs.gh-with-image];
            };
            default = gh-image;
          };
        })
        systems);

    # `nix fmt`: Biome through treefmt, with Biome's configuration here and
    # nowhere else. treefmt-nix renders it into the store and passes it with
    # --config-path.
    formatter = nixpkgs.lib.genAttrs ["aarch64-darwin" "x86_64-linux" "x86_64-darwin" "aarch64-linux"] (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      (treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.biome = {
          enable = true;
          # treefmt-nix only knows the schemas of Biome 1.x and 2.3.x and falls
          # back to 2.1.2 for anything else, which rejects options 2.4 accepts.
          # The schema shipped in the Biome source always matches pkgs.biome.
          validate.schema = "${pkgs.biome.src}/packages/@biomejs/biome/configuration_schema.json";
          settings = {
            assist = {
              actions = {
                source = {
                  organizeImports = {
                    level = "on";
                    options.groups = [
                      [":BUN:" ":NODE:"]
                      ":BLANK_LINE:"
                      ":PACKAGE:"
                      ":BLANK_LINE:"
                      "#~/**/*"
                      ":BLANK_LINE:"
                      "#@/**/*"
                      ":BLANK_LINE:"
                      ["#$/**/*" "#$$/**/*" "#%/**/*"]
                    ];
                  };
                };
              };
            };
            formatter = {
              indentStyle = "space";
              lineWidth = 120;
            };
            javascript = {formatter = {quoteStyle = "single";};};
            linter = {
              enabled = true;
              rules = {
                a11y = {
                  noStaticElementInteractions = {level = "warn";};
                  noSvgWithoutTitle = {level = "warn";};
                  useAltText = {level = "warn";};
                  useButtonType = {level = "warn";};
                  useHtmlLang = {level = "warn";};
                  useIframeTitle = {level = "warn";};
                  useKeyWithClickEvents = {level = "warn";};
                };
                complexity = {
                  noArguments = {level = "warn";};
                  noBannedTypes = {level = "warn";};
                  noCommaOperator = {level = "warn";};
                  noExcessiveCognitiveComplexity = {level = "warn";};
                  noForEach = {level = "off";};
                  noStaticOnlyClass = {level = "warn";};
                  noUselessCatch = {level = "warn";};
                  noUselessFragments = {level = "warn";};
                  noUselessTernary = {level = "error";};
                  useSimplifiedLogicExpression = {level = "off";};
                };
                correctness = {
                  noConstantCondition = {level = "warn";};
                  noEmptyPattern = {level = "warn";};
                  noInvalidUseBeforeDeclaration = {level = "warn";};
                  noSelfAssign = {level = "warn";};
                  noUnsafeOptionalChaining = {level = "warn";};
                  noUnusedImports = {
                    fix = "safe";
                    level = "error";
                  };
                  noUnusedVariables = {level = "warn";};
                  useExhaustiveDependencies = {level = "warn";};
                  useHookAtTopLevel = {level = "error";};
                  useJsxKeyInIterable = {level = "off";};
                };
                performance = {noAccumulatingSpread = {level = "warn";};};
                recommended = true;
                security = {noDangerouslySetInnerHtml = {level = "warn";};};
                style = {
                  noImplicitBoolean = {level = "off";};
                  noNegationElse = {level = "error";};
                  noNonNullAssertion = {level = "off";};
                  noParameterAssign = {level = "warn";};
                  noRestrictedImports = {
                    level = "error";
                    options = {
                      paths = {
                        "assert" = "Not permitted, see penalty at https://github.com/nodejs/node/issues/52677";
                        "node:assert" = "Not permitted, see penalty at https://github.com/nodejs/node/issues/52677";
                      };
                    };
                  };
                  useBlockStatements = {level = "error";};
                  useConsistentObjectDefinitions = {level = "error";};
                  useConst = {level = "warn";};
                  useDefaultParameterLast = {level = "off";};
                  useFilenamingConvention = {
                    level = "error";
                    options = {filenameCases = ["kebab-case"];};
                  };
                };
                suspicious = {
                  noArrayIndexKey = {level = "warn";};
                  noAssignInExpressions = {level = "warn";};
                  noConfusingVoidType = {level = "off";};
                  noConsole = {
                    level = "error";
                    options = {allow = ["assert" "debug" "error" "info" "time" "timeEnd" "trace" "warn"];};
                  };
                  noControlCharactersInRegex = {level = "warn";};
                  noDuplicateCase = {level = "warn";};
                  noExplicitAny = {level = "warn";};
                  noFallthroughSwitchClause = {level = "warn";};
                  noFocusedTests = {level = "error";};
                  noImplicitAnyLet = {level = "warn";};
                  noPrototypeBuiltins = {level = "warn";};
                  noRedeclare = {level = "warn";};
                  noShadowRestrictedNames = {level = "warn";};
                  noSkippedTests = {level = "off";};
                  noTsIgnore = {level = "off";};
                  useDefaultSwitchClauseLast = {level = "warn";};
                };
              };
            };
            overrides = [
              {
                formatter = {lineWidth = 1;};
                includes = ["**/package.json"];
              }
            ];
          };
        };
      })
      .config
      .build
      .wrapper);
  };
}
