import { ObsoleteRequest, ResearchControl, ResearchRequired, ResearchUnavailable } from './control.mjs';

export const researchTool = {
  name: 'research_gate',
  description: 'Record the kata decision. Choose research, or request an independent waiver with a reason. Complete research by identifying the evidence actually retrieved and explaining how the sources and observations agree or conflict.',
  inputSchema: {
    type: 'object',
    properties: {
      action: { enum: ['research', 'complete', 'waiver'] },
      reason: { type: 'string' },
      sources: { type: 'array', items: { type: 'string' } },
      observations: { type: 'array', items: { type: 'string' } },
      comparison: { type: 'string' },
    },
    required: ['action'],
    additionalProperties: false,
  },
};

function references(list) {
  return Array.isArray(list) && list.length > 0 && list.every((id) => typeof id === 'string' && id);
}

export class ResearchSession {
  #turn;
  #observations = new Map();
  #control = new ResearchControl((id) => this.#observations.get(id)?.reread());

  begin(request) {
    this.#observations.clear();
    this.#turn = this.#control.begin(request);
    return this.#turn;
  }

  cancel(turn) {
    if (this.#turn !== turn) return;
    this.#turn = undefined;
    this.#observations.clear();
    this.#control.cancel(turn);
  }

  #requireCurrent(turn) {
    if (!turn || turn !== this.#turn) {
      throw new ObsoleteRequest('This request was cancelled or replaced by a newer input.');
    }
  }

  capture(turn, id, value, reread) {
    this.#requireCurrent(turn);
    if (typeof id !== 'string' || !id || typeof value !== 'string' || typeof reread !== 'function') {
      throw new TypeError('Invalid observed evidence.');
    }
    this.#observations.set(id, { id, value, reread });
  }

  async submit(turn, input, judge) {
    this.#requireCurrent(turn);
    switch (input?.action) {
      case 'research':
        this.#control.requestResearch(turn);
        return { status: 'research' };
      case 'waiver': {
        const decision = await this.#control.requestWaiver(turn, input.reason, judge);
        return { status: decision.verdict, reason: decision.reason };
      }
      case 'complete':
        await this.#finishResearch(turn, input);
        return { status: 'researched' };
      default:
        throw new ResearchRequired('Use a valid research decision.');
    }
  }

  async #finishResearch(turn, { sources, observations, comparison }) {
    if (!references(sources) || !references(observations)
      || typeof comparison !== 'string' || !comparison.trim()) {
      throw new ResearchRequired('Identify the sources and observations and explain their consistency.');
    }
    const sourceIds = new Set(sources);
    if (observations.some((id) => sourceIds.has(id))) {
      throw new ResearchRequired('Cite different evidence for the source and for the observed state.');
    }

    const ids = [...new Set([...sources, ...observations])];
    const evidence = ids.map((id) => this.#observations.get(id));
    if (evidence.some((item) => !item)) {
      throw new ResearchRequired('Fetch the cited evidence in this request before using it.');
    }

    for (const item of evidence) {
      let observed;
      try {
        observed = await item.reread();
      } catch (cause) {
        this.#requireCurrent(turn);
        throw new ResearchUnavailable('A cited observation is unavailable. Fetch it again.', { cause });
      }
      this.#requireCurrent(turn);
      if (observed !== item.value || this.#observations.get(item.id) !== item) {
        throw new ResearchRequired('A cited observation changed. Get the new value and compare it with the retained evidence.');
      }
    }
    if (evidence.some((item) => this.#observations.get(item.id) !== item)) {
      throw new ResearchRequired('Research changed during the check. Compare the new evidence.');
    }
    this.#control.recordResearch(turn, evidence);
  }

  check(turn) {
    return this.#control.check(turn);
  }

  assertEligible(turn) {
    this.#control.assertEligible(turn);
  }

  permit(turn) {
    return this.#control.permit(turn);
  }

  preparePublish(turn) {
    return this.#control.preparePublish(turn);
  }
}
