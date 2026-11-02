import type { ReactNode } from "react";
import { ToolStateTable, type ToolLine } from "@/components/tool-state-table";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import type { ProfileDetail } from "@/lib/profile-base";
import {
  CONTEXT_CAP,
  CONTEXT_MINIMUM,
  OLLAMA_MCP_SERVERS,
  PARAMETER_RANGES,
  PROFILE_ENV_FIELDS,
  envFieldsByGroup,
  toolStatesFor,
  type EnvChoice,
  type ProfileEnvField,
  type ProfileOverride,
} from "@/lib/profile-rules";
import {
  withContext,
  withEnv,
  withMcp,
  withParameter,
  withSandbox,
  withThinking,
  withToolState,
} from "@/lib/profile-draft";
import type { ToolRow, ToolState } from "@/lib/tool-states";

export type ProfileUpdate = (
  change: (current: ProfileOverride) => ProfileOverride,
) => void;

export type ProfileTabProps = {
  detail: ProfileDetail;
  draft: ProfileOverride;
  saved: ProfileOverride;
  update: ProfileUpdate;
};

type FieldProps = Pick<ProfileTabProps, "detail" | "draft" | "update">;

export function ProfileToolsTab({
  detail,
  draft,
  saved,
  update,
}: ProfileTabProps) {
  const rows = detail.base.tools.map(toolLine);
  return (
    <ToolStateTable
      rows={rows}
      states={stateByName(rows, draft)}
      options={(name) => toolStatesFor(detail.kind, name)}
      isChanged={(name) =>
        (draft.tools?.[name] ?? "default") !==
        (saved.tools?.[name] ?? "default")
      }
      onChange={(name, state) =>
        update((current) => withToolState(current, name, state))
      }
    />
  );
}

function toolLine(tool: ToolRow): ToolLine {
  return {
    name: tool.name,
    description: tool.description,
    baseline: tool.disabled ? `${tool.permission}, off` : tool.permission,
  };
}

function stateByName(
  rows: readonly ToolLine[],
  draft: ProfileOverride,
): Record<string, ToolState> {
  return Object.fromEntries(
    rows.map((row) => [row.name, draft.tools?.[row.name] ?? "default"]),
  );
}

export function ProfileModelTab({ detail, draft, update }: ProfileTabProps) {
  if (detail.kind === "claude-code") {
    return <SandboxSwitch enabled={draft.sandbox !== false} update={update} />;
  }
  return (
    <div className="flex flex-col gap-4 text-sm">
      <p className="text-muted-foreground">
        Sandbox is always on for Ollama profiles.
      </p>
      <ContextField detail={detail} draft={draft} update={update} />
      <ThinkingSwitch enabled={draft.thinking === true} update={update} />
      <ParameterFields detail={detail} draft={draft} update={update} />
    </div>
  );
}

function ThinkingSwitch({
  enabled,
  update,
}: Pick<FieldProps, "update"> & { enabled: boolean }) {
  return (
    <label className="flex items-center gap-2 text-sm">
      <input
        type="checkbox"
        role="switch"
        aria-label="Thinking enabled"
        checked={enabled}
        onChange={(event) =>
          update((current) =>
            withThinking(current, event.target.checked ? true : null),
          )
        }
      />
      Model thinking on (off by default: Claude Code asks for high effort on
      every turn)
    </label>
  );
}

function SandboxSwitch({
  enabled,
  update,
}: Pick<FieldProps, "update"> & { enabled: boolean }) {
  return (
    <label className="flex items-center gap-2 text-sm">
      <input
        type="checkbox"
        role="switch"
        aria-label="Sandbox enabled"
        checked={enabled}
        onChange={(event) =>
          update((current) =>
            withSandbox(current, event.target.checked ? null : false),
          )
        }
      />
      Sandbox enabled for this profile
    </label>
  );
}

function ContextField({ detail, draft, update }: FieldProps) {
  return (
    <FieldRow label="Context tokens">
      <Input
        type="number"
        aria-label="Context tokens"
        min={CONTEXT_MINIMUM}
        max={CONTEXT_CAP}
        step={1}
        placeholder={String(detail.base.context ?? "default")}
        value={draft.context ?? ""}
        onChange={(event) =>
          update((current) =>
            withContext(current, numberOrNull(event.target.value)),
          )
        }
      />
    </FieldRow>
  );
}

function ParameterFields({ detail, draft, update }: FieldProps) {
  return (
    <div className="flex flex-col gap-2">
      {Object.keys(PARAMETER_RANGES).map((name) => (
        <FieldRow key={name} label={name}>
          <Input
            type="number"
            aria-label={name}
            step="any"
            placeholder={String(detail.base.parameters[name] ?? "unset")}
            value={draft.parameters?.[name] ?? ""}
            onChange={(event) =>
              update((current) =>
                withParameter(current, name, numberOrNull(event.target.value)),
              )
            }
          />
        </FieldRow>
      ))}
    </div>
  );
}

function FieldRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="grid grid-cols-[10rem_1fr] items-center gap-3">
      <span className="font-mono text-muted-foreground">{label}</span>
      {children}
    </div>
  );
}

export function ProfileMcpHooksTab({ detail, draft, update }: ProfileTabProps) {
  return (
    <div className="flex flex-col gap-6 text-sm">
      <Section title="MCP servers">
        {detail.base.mcpServers.length === 0 ? (
          <p className="text-muted-foreground">
            Claude Code uses the MCP servers in your own settings.
          </p>
        ) : (
          OLLAMA_MCP_SERVERS.map((name) => (
            <McpSwitch
              key={name}
              name={name}
              enabled={draft.mcp?.[name] !== false}
              update={update}
            />
          ))
        )}
      </Section>
      <Section title="Hooks (read-only)">
        {detail.base.hooks.length === 0 ? (
          <p className="text-muted-foreground">
            No hooks in the rendered settings.
          </p>
        ) : (
          <HookTable detail={detail} />
        )}
      </Section>
    </div>
  );
}

function McpSwitch({
  name,
  enabled,
  update,
}: {
  name: string;
  enabled: boolean;
  update: ProfileUpdate;
}) {
  return (
    <label className="flex items-center gap-2">
      <input
        type="checkbox"
        role="switch"
        aria-label={`MCP ${name}`}
        checked={enabled}
        onChange={(event) =>
          update((current) =>
            withMcp(current, name, event.target.checked ? null : false),
          )
        }
      />
      <span className="font-mono">{name}</span>
    </label>
  );
}

function HookTable({ detail }: { detail: ProfileDetail }) {
  return (
    <table className="w-full text-left">
      <thead>
        <tr className="border-b text-muted-foreground">
          <th className="py-2 pr-3 font-medium">Event</th>
          <th className="py-2 pr-3 font-medium">Matcher</th>
          <th className="py-2 pr-3 font-medium">Script</th>
        </tr>
      </thead>
      <tbody>
        {detail.base.hooks.map((hook) => (
          <tr
            key={`${hook.event}-${hook.matcher}-${hook.command}`}
            className="border-b"
          >
            <td className="py-2 pr-3">{hook.event}</td>
            <td className="py-2 pr-3 font-mono">{hook.matcher}</td>
            <td className="py-2 pr-3 font-mono">{hook.command}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export function ProfileEnvTab({ detail, draft, update }: FieldProps) {
  const fields = PROFILE_ENV_FIELDS.filter(
    (field) => !field.ollamaOnly || detail.kind === "ollama",
  );
  return (
    <div className="flex flex-col gap-6 text-sm">
      {envFieldsByGroup(fields).map(({ group, fields: grouped }) => (
        <Section key={group} title={group}>
          <div className="flex flex-col gap-4">
            {grouped.map((field) => (
              <EnvField
                key={field.key}
                field={field}
                value={draft.env?.[field.key]}
                update={update}
              />
            ))}
          </div>
        </Section>
      ))}
    </div>
  );
}

type EnvFieldProps = {
  field: ProfileEnvField;
  value: string | undefined;
  update: ProfileUpdate;
};

function EnvField({ field, value, update }: EnvFieldProps) {
  const setValue = (next: string | null) =>
    update((current) => withEnv(current, field.key, next));
  return (
    <div className="grid grid-cols-[14rem_1fr] items-start gap-3">
      <div className="flex flex-col gap-1">
        <span>{field.label}</span>
        <span className="text-xs text-muted-foreground">{field.help}</span>
      </div>
      <EnvInput field={field} value={value} setValue={setValue} />
    </div>
  );
}

type EnvInputProps = {
  field: ProfileEnvField;
  value: string | undefined;
  setValue: (next: string | null) => void;
};

function EnvInput({ field, value, setValue }: EnvInputProps) {
  if (field.kind === "switch") {
    return <EnvSwitch field={field} value={value} setValue={setValue} />;
  }
  if (field.kind === "choice") {
    return <EnvChoice field={field} value={value} setValue={setValue} />;
  }
  return <EnvNumber field={field} value={value} setValue={setValue} />;
}

function EnvChoice({
  field,
  value,
  setValue,
}: EnvInputProps & { field: Extract<ProfileEnvField, { kind: "choice" }> }) {
  return (
    <Select
      aria-label={field.label}
      value={value ?? "default"}
      onChange={(event) => setValue(envOrNull(event.target.value))}
    >
      <option value="default">
        default ({choiceWord(field.choices, field.defaultValue)})
      </option>
      {field.choices.map((choice) => (
        <option key={choice.value} value={choice.value}>
          {choice.word}
        </option>
      ))}
    </Select>
  );
}

function EnvSwitch({ field, value, setValue }: EnvInputProps) {
  return (
    <Select
      aria-label={field.label}
      value={value ?? "default"}
      onChange={(event) => setValue(envOrNull(event.target.value))}
    >
      <option value="default">
        default ({switchWord(field.defaultValue)})
      </option>
      <option value="0">off</option>
      <option value="1">on</option>
    </Select>
  );
}

function EnvNumber({
  field,
  value,
  setValue,
}: EnvInputProps & { field: Extract<ProfileEnvField, { kind: "number" }> }) {
  return (
    <Input
      type="number"
      aria-label={field.label}
      min={field.range.min}
      max={field.range.max}
      step={field.range.step}
      placeholder={field.defaultValue}
      value={value ?? ""}
      onChange={(event) => setValue(textOrNull(event.target.value))}
    />
  );
}

function choiceWord(choices: readonly EnvChoice[], value: string): string {
  return choices.find((choice) => choice.value === value)?.word ?? value;
}

function switchWord(value: string): string {
  return value === "1" ? "on" : "off";
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-2">
      <h2 className="font-medium">{title}</h2>
      {children}
    </section>
  );
}

function numberOrNull(text: string): number | null {
  return text === "" ? null : Number(text);
}

function envOrNull(value: string): string | null {
  return value === "default" ? null : value;
}

function textOrNull(value: string): string | null {
  return value === "" ? null : value;
}
