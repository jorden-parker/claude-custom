import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { ReactNode } from "react";
import { ToolStateTable, type ToolLine } from "@/components/tool-state-table";
import { Input } from "@/components/ui/input";
import { Select } from "@/components/ui/select";
import type { ProfileDetail } from "@/lib/profile-base";
import {
  CONTEXT_CAP,
  CONTEXT_MINIMUM,
  OUTPUT_TOKENS_RANGE,
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
  withOutputTokens,
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
      <OutputTokensField detail={detail} draft={draft} update={update} />
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
    <Label className="flex items-center gap-2">
      <Switch
        aria-label="Thinking enabled"
        checked={enabled}
        onCheckedChange={(next) =>
          update((current) => withThinking(current, next ? true : null))
        }
      />
      Model thinking on (off by default; the level comes from the Env tab
      thinking effort select, xhigh unless set)
    </Label>
  );
}

function SandboxSwitch({
  enabled,
  update,
}: Pick<FieldProps, "update"> & { enabled: boolean }) {
  return (
    <Label className="flex items-center gap-2">
      <Switch
        aria-label="Sandbox enabled"
        checked={enabled}
        onCheckedChange={(next) =>
          update((current) => withSandbox(current, next ? null : false))
        }
      />
      Sandbox enabled for this profile
    </Label>
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

function OutputTokensField({ detail, draft, update }: FieldProps) {
  return (
    <FieldRow label="Output tokens per reply">
      <div className="flex flex-col gap-1">
        <Input
          type="number"
          aria-label="Output tokens per reply"
          min={OUTPUT_TOKENS_RANGE.min}
          max={OUTPUT_TOKENS_RANGE.max}
          step={OUTPUT_TOKENS_RANGE.step}
          placeholder={String(detail.base.outputTokens ?? "default")}
          value={draft.output_tokens ?? ""}
          onChange={(event) =>
            update((current) =>
              withOutputTokens(current, numberOrNull(event.target.value)),
            )
          }
        />
        <span className="text-xs text-muted-foreground">
          Caps one reply (num_predict and CLAUDE_CODE_MAX_OUTPUT_TOKENS); decode
          is the slow path on a laptop, so a lower cap costs less per reply.
        </span>
      </div>
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
    <div className="grid grid-cols-1 gap-1 sm:grid-cols-[10rem_1fr] sm:items-center sm:gap-3">
      <span className="font-mono text-muted-foreground">{label}</span>
      {children}
    </div>
  );
}

export function ProfileHooksTab({ detail }: ProfileTabProps) {
  return (
    <div className="flex flex-col gap-6 text-sm">
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

function HookTable({ detail }: { detail: ProfileDetail }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Event</TableHead>
          <TableHead>Matcher</TableHead>
          <TableHead>Script</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {detail.base.hooks.map((hook) => (
          <TableRow key={`${hook.event}-${hook.matcher}-${hook.command}`}>
            <TableCell>{hook.event}</TableCell>
            <TableCell className="font-mono">{hook.matcher}</TableCell>
            <TableCell className="font-mono">{hook.command}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
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
    <div className="grid grid-cols-1 gap-2 md:grid-cols-[14rem_1fr] md:items-start md:gap-3">
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
