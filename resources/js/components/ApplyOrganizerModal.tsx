import React from 'react';
import { useForm } from '@inertiajs/react';
import { KeyRound, ShieldCheck, X, AlertCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

interface Props {
  isOpen: boolean;
  onClose: () => void;
  applicationStatus?: 'pending' | 'approved' | 'rejected' | null;
  rejectionReason?: string | null;
}

const GOLD = '#C9973E';

export default function ApplyOrganizerModal({
  isOpen,
  onClose,
  applicationStatus,
  rejectionReason,
}: Props) {
  const { data, setData, post, processing, errors, reset } = useForm({
    org_code: '',
    secret_key: '',
    organization_name: '',
    position: '',
    justification: '',
  });

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    // Direct endpoint post to avoid Ziggy route resolution issues
    post('/organizer/apply', {
      onSuccess: () => {
        reset();
        onClose();
      },
    });
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/60 backdrop-blur-xs flex items-center justify-center p-4">
      <div className="bg-card text-card-foreground rounded-2xl shadow-2xl max-w-lg w-full p-6 space-y-6 relative border border-border">
        
        {/* Close Button */}
        <button
          onClick={onClose}
          type="button"
          className="absolute top-4 right-4 text-muted-foreground hover:text-foreground transition p-1 rounded-lg hover:bg-muted"
        >
          <X className="w-5 h-5" />
        </button>

        {/* Modal Header */}
        <div className="flex items-center gap-3 border-b border-border pb-4">
          <div className="p-3 bg-[#03045E] text-[#FFD600] rounded-xl shrink-0">
            <KeyRound className="w-6 h-6" />
          </div>
          <div>
            <h2 className="text-lg font-bold text-foreground">
              Apply as Event Organizer
            </h2>
            <p className="text-xs text-muted-foreground">
              Enter your organization key pair provided by an administrator.
            </p>
          </div>
        </div>

        {/* Existing Application Status Banner */}
        {applicationStatus === 'pending' && (
          <div className="p-4 bg-amber-500/10 border border-amber-500/20 rounded-xl flex items-start gap-3">
            <ShieldCheck className="w-5 h-5 text-amber-600 dark:text-amber-400 shrink-0 mt-0.5" />
            <div className="text-sm text-amber-800 dark:text-amber-300 space-y-1">
              <p className="font-semibold">Application Under Review</p>
              <p className="text-xs">
                Your application has been received and is waiting for administrator approval.
              </p>
            </div>
          </div>
        )}

        {applicationStatus === 'rejected' && (
          <div className="p-4 bg-destructive/10 border border-destructive/20 rounded-xl flex items-start gap-3">
            <AlertCircle className="w-5 h-5 text-destructive shrink-0 mt-0.5" />
            <div className="text-sm text-destructive space-y-1">
              <p className="font-semibold">Previous Application Rejected</p>
              <p className="text-xs">
                Reason: {rejectionReason || 'Key pair verification failed.'}
              </p>
              <p className="text-xs font-medium pt-1">You may re-apply below using a valid key pair.</p>
            </div>
          </div>
        )}

        {/* Key Pair Form */}
        {applicationStatus !== 'pending' && (
          <form onSubmit={handleSubmit} className="space-y-4">
            
            {/* Key Pair Inputs */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 bg-muted/40 p-4 rounded-xl border border-border">
              <div className="grid gap-1.5">
                <Label htmlFor="org_code" className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  Organization Code
                </Label>
                <Input
                  id="org_code"
                  type="text"
                  value={data.org_code}
                  onChange={e => setData('org_code', e.target.value.toUpperCase())}
                  placeholder="ORG-CS-2026"
                  className="font-mono bg-background text-slate-900 uppercase text-xs"
                  required
                />
                {errors.org_code && <p className="text-destructive text-xs">{errors.org_code}</p>}
              </div>

              <div className="grid gap-1.5">
                <Label htmlFor="secret_key" className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  Secret Key
                </Label>
                <Input
                  id="secret_key"
                  type="password"
                  value={data.secret_key}
                  onChange={e => setData('secret_key', e.target.value)}
                  placeholder="KEY-XXXXXXXX"
                  className="font-mono bg-background text-slate-900 text-xs"
                  required
                />
                {errors.secret_key && <p className="text-destructive text-xs">{errors.secret_key}</p>}
              </div>
            </div>

            {/* Applicant Org Details */}
            <div className="space-y-4">
              <div className="grid gap-1.5">
                <Label htmlFor="organization_name" className="text-xs font-medium">
                  Student Organization / Club Name
                </Label>
                <Input
                  id="organization_name"
                  type="text"
                  value={data.organization_name}
                  onChange={e => setData('organization_name', e.target.value)}
                  placeholder="e.g. Computer Science Society"
                  className="bg-background text-slate-900 text-xs"
                  required
                />
                {errors.organization_name && <p className="text-destructive text-xs">{errors.organization_name}</p>}
              </div>

              <div className="grid gap-1.5">
                <Label htmlFor="position" className="text-xs font-medium">
                  Your Position in Org
                </Label>
                <Input
                  id="position"
                  type="text"
                  value={data.position}
                  onChange={e => setData('position', e.target.value)}
                  placeholder="e.g. Event Lead / Vice President"
                  className="bg-background text-slate-900 text-xs"
                  required
                />
                {errors.position && <p className="text-destructive text-xs">{errors.position}</p>}
              </div>

              <div className="grid gap-1.5">
                <Label htmlFor="justification" className="text-xs font-medium">
                  Brief Justification (Optional)
                </Label>
                <textarea
                  id="justification"
                  value={data.justification}
                  onChange={e => setData('justification', e.target.value)}
                  placeholder="Explain why you are requesting access..."
                  className="w-full rounded-md border border-input bg-background text-slate-900 px-3 py-2 text-xs focus-visible:outline-hidden focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50"
                  rows={2}
                />
              </div>
            </div>

            {/* Modal Actions */}
            <div className="flex justify-end gap-3 pt-4 border-t border-border">
              <Button
                type="button"
                variant="outline"
                onClick={onClose}
              >
                Cancel
              </Button>
              <Button
                type="submit"
                disabled={processing}
                style={{ backgroundColor: GOLD }}
                className="text-white hover:opacity-90 transition-opacity font-semibold"
              >
                Submit Application
              </Button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}