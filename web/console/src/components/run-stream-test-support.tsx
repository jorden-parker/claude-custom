export class FakeRunEventSource {
  static opened: FakeRunEventSource[] = [];
  onmessage: ((message: MessageEvent) => void) | null = null;
  closed = false;

  constructor(readonly url: string) {
    FakeRunEventSource.opened.push(this);
  }

  close() {
    this.closed = true;
  }

  receive(event: Record<string, unknown>) {
    this.onmessage?.({
      data: JSON.stringify(event),
      lastEventId: "",
    } as MessageEvent);
  }

  start(command: string, label: string) {
    this.receive({
      kind: "start",
      command,
      label,
      started_at: "2026-11-02T14:02:11Z",
      pid: 42,
    });
  }

  lines(texts: readonly string[]) {
    texts.forEach((text, index) =>
      this.receive({ kind: "line", stream: "stdout", text, t: index }),
    );
  }

  end(code = 0) {
    this.receive({ kind: "end", code, t: 9 });
  }
}
