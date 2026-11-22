class ResearchError extends Error {
  constructor(message, options) {
    super(message, options);
    this.name = new.target.name;
  }
}

export class ResearchUnavailable extends ResearchError {}
export class ResearchRequired extends ResearchError {}
export class ResearchRefused extends ResearchError {}
export class ObsoleteRequest extends ResearchError {}

export class ResearchControl {
  #current;
  #observe;

  constructor(observe) {
    this.#observe = observe;
  }

  begin(request) {
    const turn = Symbol();
    this.#current = { turn, request, phase: 'decision', evidence: new Map() };
    return turn;
  }

  cancel(turn) {
    if (this.#current?.turn === turn) {
      this.#current = undefined;
    }
  }

  #active(turn) {
    const current = this.#current;
    if (!current || current.turn !== turn) {
      throw new ObsoleteRequest('This request was cancelled or replaced by a newer input.');
    }
    if (current.phase === 'refused') {
      throw new ResearchRefused(current.refusal);
    }
    return current;
  }

  requestResearch(turn) {
    const current = this.#active(turn);
    if (current.phase === 'research') return;
    if (current.phase !== 'decision') {
      throw new ResearchRequired('A decision for this request is already in progress or complete.');
    }
    current.phase = 'research';
  }

  recordResearch(turn, observations) {
    const current = this.#active(turn);
    if (current.phase !== 'research') {
      throw new ResearchRequired('Research has not been requested.');
    }

    const evidence = new Map();
    for (const { id, value } of observations) {
      if (typeof id !== 'string' || !id || typeof value !== 'string' || evidence.has(id)) {
        throw new ResearchRequired('Research has a missing or ambiguous observation.');
      }
      evidence.set(id, value);
    }
    if (!evidence.size || [...current.evidence.keys()].some((id) => !evidence.has(id))) {
      throw new ResearchRequired('Compare new observations with the evidence already used.');
    }

    current.evidence = evidence;
    current.phase = 'researched';
  }

  async requestWaiver(turn, reason, judge) {
    const current = this.#active(turn);
    if (current.phase !== 'decision' || typeof reason !== 'string' || !reason.trim()) {
      throw new ResearchRequired('A new waiver needs a reason and an undecided request.');
    }
    current.phase = 'judging';
    let decision;
    try {
      decision = await judge(current.request, reason);
      if (!['approved', 'research', 'refused'].includes(decision?.verdict)
        || typeof decision.reason !== 'string' || !decision.reason.trim()) {
        throw new TypeError('The judge returned no valid decision.');
      }
    } catch (cause) {
      this.#active(turn);
      current.phase = 'decision';
      throw new ResearchUnavailable('The independent decision failed. Research or retry before continuing.', { cause });
    }

    this.#active(turn);
    if (decision.verdict === 'refused') {
      current.phase = 'refused';
      current.refusal = decision.reason;
      throw new ResearchRefused(decision.reason);
    }
    current.phase = decision.verdict === 'approved' ? 'waived' : 'research';
    return decision;
  }

  async #check(turn) {
    const current = this.#active(turn);
    if (current.phase === 'waived') {
      return current.evidence;
    }
    if (current.phase !== 'researched') {
      throw new ResearchRequired('Wait for research or independent permission to omit it.');
    }

    const evidence = current.evidence;
    const checked = await Promise.all([...evidence].map(async ([id, previous]) => {
      try {
        const observed = await this.#observe(id);
        if (typeof observed === 'string') return { id, previous, observed, available: true };
      } catch {
        return { id, available: false };
      }
      return { id, available: false };
    }));

    this.#active(turn);
    if (current.evidence !== evidence || current.phase !== 'researched') {
      throw new ResearchRequired('Research changed during the check. Verify it again.');
    }
    const unavailable = checked.filter(({ available }) => !available);
    if (unavailable.length) {
      current.phase = 'research';
      const error = new ResearchUnavailable('Evidence could not be checked. Read the affected observations again.');
      error.observationIds = unavailable.map(({ id }) => id);
      throw error;
    }
    const changes = checked.filter(({ previous, observed }) => previous !== observed);
    if (changes.length) {
      current.phase = 'research';
      const error = new ResearchRequired('A premise changed. Research it again and compare it with the existing evidence.');
      error.changes = changes;
      throw error;
    }
    return evidence;
  }

  async check(turn) {
    this.#requireSameEvidence(turn, await this.#check(turn));
  }

  assertEligible(turn) {
    const current = this.#active(turn);
    if (!['researched', 'waived'].includes(current.phase)) {
      throw new ResearchRequired('Wait for research or independent permission to omit it.');
    }
  }

  #requireSameEvidence(turn, evidence) {
    const current = this.#active(turn);
    if (current.evidence !== evidence || !['waived', 'researched'].includes(current.phase)) {
      throw new ResearchRequired('Research changed. Start again with the new evidence.');
    }
  }

  permit(turn) {
    const { evidence } = this.#active(turn);
    this.#requireSameEvidence(turn, evidence);
    return async (display) => {
      await this.#check(turn);
      this.#requireSameEvidence(turn, evidence);
      return display();
    };
  }

  async preparePublish(turn) {
    const evidence = await this.#check(turn);
    this.#requireSameEvidence(turn, evidence);
    return this.permit(turn);
  }

  async publish(turn, generate, display) {
    const release = await this.preparePublish(turn);
    const content = await generate();
    return release(() => display(content));
  }
}
