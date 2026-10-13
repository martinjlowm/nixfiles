import { App, Job, RunnerLabel, Stack, Workflow } from '@factbird/cdkactions';

// Each action runs by commit, since whoever controls a tag can move it.
const checkout = {
  uses: 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1', // v7.0.1
};

const installNix = {
  name: 'Install Nix',
  uses: 'DeterminateSystems/nix-installer-action@3138316df39ed29be04236d7ffc686fa525866aa', // v23
};

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
    checkout,
    installNix,
    {
      name: 'Update the nixpkgs input',
      uses: 'DeterminateSystems/update-flake-lock@da03c0f078bc4b2c37ee4f7e072d34bf8f188bb3', // v29
      with: {
        inputs: 'nixpkgs',
        branch: 'chore/nixpkgs-bump',
        'commit-msg': 'chore(nix): bump nixpkgs-26.05-chilled',
        'pr-title': 'chore(nix): bump nixpkgs-26.05-chilled',
        'pr-labels': 'dependencies',
      },
    },
  ],
});

app.synth();
