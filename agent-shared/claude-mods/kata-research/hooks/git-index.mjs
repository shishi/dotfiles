export const gitIndexTool = {
  name: 'read_git_index',
  description: 'Check whether one path is tracked in the Git index of the current directory.',
  inputSchema: {
    type: 'object',
    properties: { path: { type: 'string', description: 'Path relative to the current directory.' } },
    required: ['path'],
    additionalProperties: false,
  },
};

export async function observeGitIndex(path, run) {
  if (typeof path !== 'string' || !path || /[\x00-\x1f\x7f]/.test(path)
    || path.split('/').some((part) => !part || part === '.' || part === '..')) {
    throw new Error('Use a file path relative to the current directory.');
  }
  const command = ['git', 'ls-files', '-z', '--cached', '--deduplicate', '--', `:(literal)${path}`];
  const reread = async () => {
    const output = await run(command);
    if (typeof output !== 'string' || (output && !output.endsWith('\0'))) {
      throw new Error('The Git index read did not produce a complete file listing.');
    }
    return output.split('\0').includes(path) ? 'tracked' : 'untracked';
  };
  return { key: `git-index:${path}`, value: await reread(), reread };
}
