"use client";

import { Loader2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState, type ReactNode } from "react";
import { Button } from "@/components/ui/button";
import type { CommandParams } from "@/lib/console-commands";
import { postRun } from "@/lib/post-run";

type StartRunButtonProps = {
  command: string;
  params: CommandParams;
  children: ReactNode;
  stay?: boolean;
  onStarted?: (id: string) => void;
  disabled?: boolean;
};

export function StartRunButton({
  command,
  params,
  children,
  stay = false,
  onStarted,
  disabled = false,
}: StartRunButtonProps) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const start = async () => {
    setPending(true);
    setMessage(null);
    const result = await postRun(command, params);
    if (result.ok) {
      if (stay) {
        onStarted?.(result.id);
        setPending(false);
        return;
      }
      router.push(`/runs/${encodeURIComponent(result.id)}`);
      return;
    }
    setMessage(result.message);
    setPending(false);
  };

  return (
    <div className="flex flex-col items-start gap-2">
      <Button onClick={start} disabled={pending || disabled}>
        {pending ? <Loader2 className="animate-spin" /> : null}
        {children}
      </Button>
      {message === null ? null : <p className="text-sm text-red-700 dark:text-red-400">{message}</p>}
    </div>
  );
}
