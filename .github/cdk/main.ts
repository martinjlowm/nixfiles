import {
  App,
  checkoutV7,
  DependabotActionPinSync,
  Job,
  nixInstallerActionV23,
  RunnerLabel,
  Stack,
  setupBunV2,
  updateFlakeLockV29,
  Workflow,
} from '@factbird/cdkactions';

const checkout = checkoutV7.pinned('3d3c42e5aac5ba805825da76410c181273ba90b1', 'v7.0.1');
const installNix = nixInstallerActionV23.pinned('3138316df39ed29be04236d7ffc686fa525866aa', 'v23');
const updateFlakeLock = updateFlakeLockV29.pinned('da03c0f078bc4b2c37ee4f7e072d34bf8f188bb3', 'v29');
const setupBun = setupBunV2.pinned('0c5077e51419868618aeaa5fe8019c62421857d6', 'v2.2.0');

const app = new App({ outdir: '../workflows', createValidateWorkflow: false });
const stack = new Stack(app, 'nixfiles');

const nixpkgsBump = new Workflow(stack, 'nixpkgs-bump', {
  name: 'Bump nixpkgs',
  on: {
    schedule: [{ cron: '0 4 * * 1' }],
    workflowDispatch: {},
  },
  permissions: { contents: 'read' },
  concurrency: { group: 'nixpkgs-bump', cancelInProgress: false },
});

new Job(nixpkgsBump, 'bump', {
  name: 'Bump nixpkgs',
  runsOn: RunnerLabel.UBUNTU_LATEST,
  // update-flake-lock opens the pull request with GITHUB_TOKEN, because this
  // public repository has no app secret, so no workflow runs on it until
  // someone pushes to the branch or closes and reopens it.
  permissions: { contents: 'write', pullRequests: 'write' },
  steps: [
    checkout({ id: 'checkout' }),
    installNix({ name: 'Install Nix' }),
    updateFlakeLock({
      id: 'update-flake-lock',
      name: 'Update the nixpkgs input',
      with: {
        inputs: 'nixpkgs',
        branch: 'chore/nixpkgs-bump',
        commitMsg: 'chore(nix): bump nixpkgs-26.05-chilled',
        prTitle: 'chore(nix): bump nixpkgs-26.05-chilled',
        prLabels: 'dependencies',
      },
    }),
  ],
});

new DependabotActionPinSync(stack, 'dependabot-action-pin-sync', {
  sources: ['.github/cdk/main.ts'],
  synthCommand: 'bun run --cwd .github/cdk synth',
  cliCommand: '.github/cdk/node_modules/.bin/cdkactions',
  setupSteps: [
    setupBun({ id: 'setup-bun' }),
    {
      name: 'Install the workflow dependencies',
      run: 'bun install --cwd .github/cdk --frozen-lockfile',
    },
  ],
});

app.synth();
