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
import { gigabytes, namesToRemove, totalBytes, type WeightFile } from "@/lib/model-display";

type PruneConfirmProps = {
  files: WeightFile[];
  onConfirm: (names: string[]) => void;
  onCancel: () => void;
};

export function PruneConfirm({ files, onConfirm, onCancel }: PruneConfirmProps) {
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
          <AlertDialogTitle>Remove weight files</AlertDialogTitle>
          <AlertDialogDescription>
            {files.length} files, {gigabytes(totalBytes(files))} GB freed.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <ul className="flex flex-col gap-1 font-mono text-xs">
          {files.map((file) => (
            <li key={file.name}>
              {file.name} <span className="text-muted-foreground">{gigabytes(file.bytes)} GB</span>
            </li>
          ))}
        </ul>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction variant="destructive" onClick={() => onConfirm(namesToRemove(files))}>
            Remove weight files
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
