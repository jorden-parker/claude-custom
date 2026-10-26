"use client";

import { Loader2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState, type ReactNode } from "react";
import { Button } from "@/components/ui/button";
import type { CommandParams } from "@/lib/console-commands";

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
    const response = await fetch("/api/runs", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ command, params }),
    });
    if (response.status === 201) {
      const { id } = (await response.json()) as { id: string };
      if (stay) {
        onStarted?.(id);
        setPending(false);
        return;
      }
      router.push(`/runs/${encodeURIComponent(id)}`);
      return;
    }
    const { message: reason } = (await response.json()) as { message: string };
    setMessage(reason);
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
