import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { gigabytes, namesToRemove, totalBytes, type InstalledModel } from "@/lib/model-display";

type PruneConfirmProps = {
  models: InstalledModel[];
  onConfirm: (names: string[]) => void;
  onCancel: () => void;
};

export function PruneConfirm({ models, onConfirm, onCancel }: PruneConfirmProps) {
  return (
    <Card>
      <CardContent className="flex flex-col gap-3">
        <p className="text-sm font-medium">
          Remove these {models.length} models and free {gigabytes(totalBytes(models))} GB?
        </p>
        <ul className="flex flex-col gap-1 font-mono text-xs">
          {models.map((model) => (
            <li key={model.name}>
              {model.name} <span className="text-muted-foreground">{gigabytes(model.bytes)} GB</span>
            </li>
          ))}
        </ul>
        <div className="flex gap-2">
          <Button variant="destructive" onClick={() => onConfirm(namesToRemove(models))}>
            Remove these
          </Button>
          <Button variant="outline" onClick={onCancel}>
            Cancel
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
