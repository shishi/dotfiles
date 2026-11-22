export const sourceLimit = 64 * 1024;
export const publicSourceTool = {
  name: 'read_research_url',
  description: 'Obtain the text and observation identifier of a public HTTPS source using the configured Web permissions.',
  inputSchema: {
    type: 'object',
    properties: { url: { type: 'string' } },
    required: ['url'],
    additionalProperties: false,
  },
};

export function publicSourceIdentifier(input) {
  let url;
  try {
    url = new URL(input);
  } catch {
    throw new Error('Use a public HTTPS URL without credentials.');
  }
  const host = url.hostname.replace(/\.$/, '');
  if (url.protocol !== 'https:' || url.username || url.password || url.port
      || !host.includes('.') || /^[0-9.]+$/.test(host)
      || ['.localhost', '.local', '.internal', '.onion'].some((suffix) => host.endsWith(suffix))) {
    throw new Error('Use a public HTTPS URL without credentials.');
  }
  url.hash = '';
  return url.href;
}

function usableValidator(header) {
  return typeof header === 'string' && header && !/[\r\n]/.test(header);
}

function readText(response) {
  if (response.status !== 200 || typeof response.text !== 'string' || !response.text
      || response.text.includes('\0') || new TextEncoder().encode(response.text).length > sourceLimit) {
    throw new Error('The public source did not return a complete text document up to 64 KiB.');
  }
  return response.text;
}

export async function observePublicSource(input, fetch) {
  const key = publicSourceIdentifier(input);
  const original = await fetch(key, {});
  const value = readText(original);
  const { etag, 'last-modified': modified } = original.headers ?? {};
  const validators = usableValidator(etag) ? { 'If-None-Match': etag }
    : usableValidator(modified) ? { 'If-Modified-Since': modified } : {};
  return {
    key,
    value,
    async reread() {
      const current = await fetch(key, validators);
      if (current.status === 304 && Object.keys(validators).length) return value;
      return readText(current);
    },
  };
}

export function publicSourceCommand(reader, url, headers) {
  return ['python3', '-I', reader, url, JSON.stringify(headers)];
}

export function parsePublicSourceResponse(response) {
  const boundary = response.match(/\r?\n\r?\n/);
  if (!boundary) throw new Error('The HTTP response did not contain complete headers.');
  const [statusLine, ...lines] = response.slice(0, boundary.index).split(/\r?\n/);
  const status = Number(statusLine.match(/^HTTP\/\S+\s+(\d{3})/)?.[1]);
  const headers = {};
  for (const line of lines) {
    const separator = line.indexOf(':');
    const name = line.slice(0, separator).toLowerCase();
    if (name === 'etag' || name === 'last-modified') headers[name] = line.slice(separator + 1).trim();
  }
  return { status, headers, text: response.slice(boundary.index + boundary[0].length) };
}
