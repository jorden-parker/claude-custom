import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { gigabytes, namesToRemove, totalBytes, type InstalledModel } from "@/lib/model-display";

type PruneConfirmProps = {
  models: InstalledModel[];
  onConfirm: (names: string[]) => void;
  onCancel: () => void;
};

export function PruneConfirm({ models, onConfirm, onCancel }: PruneConfirmProps) {
  return (
    <AlertDialog
      open
      onOpenChange={(open) => {
        if (!open) {
          onCancel();
        }
      }}
    >
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Remove Models</AlertDialogTitle>
          <AlertDialogDescription>
            {models.length} models, {gigabytes(totalBytes(models))} GB freed.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <ul className="flex flex-col gap-1 font-mono text-xs">
          {models.map((model) => (
            <li key={model.name}>
              {model.name} <span className="text-muted-foreground">{gigabytes(model.bytes)} GB</span>
            </li>
          ))}
        </ul>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction variant="destructive" onClick={() => onConfirm(namesToRemove(models))}>
            Remove Models
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
