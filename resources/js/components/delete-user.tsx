import { useRef, useState } from 'react';
import { router } from '@inertiajs/react';
import Heading from '@/components/heading';
import InputError from '@/components/input-error';
import PasswordInput from '@/components/password-input';
import { Button } from '@/components/ui/button';
import {
    Dialog,
    DialogClose,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogTitle,
    DialogTrigger,
} from '@/components/ui/dialog';
import { Label } from '@/components/ui/label';
import { CheckCircle2, Loader2 } from 'lucide-react';

export default function DeleteUser() {
    const passwordInput = useRef<HTMLInputElement>(null);
    const [password, setPassword] = useState('');
    const [errors, setErrors] = useState<Record<string, string>>({});
    const [processing, setProcessing] = useState(false);
    const [isOpen, setIsOpen] = useState(false);
    const [showSuccessModal, setShowSuccessModal] = useState(false);

    const handleDelete = (e: React.FormEvent) => {
        e.preventDefault();
        setProcessing(true);
        setErrors({});

        // Using a direct URL string instead of Ziggy's route()
        router.delete('/profile', {
            data: { password },
            preserveScroll: true,
            onSuccess: () => {
                setProcessing(false);
                setIsOpen(false);
                setShowSuccessModal(true);

                // Keeps the success pop-up visible for 1 second before redirect
                setTimeout(() => {
                    setShowSuccessModal(false);
                }, 1000);
            },
            onError: (errs) => {
                setProcessing(false);
                setErrors(errs);
                passwordInput.current?.focus();
            },
        });
    };

    const resetAndClearErrors = () => {
        setPassword('');
        setErrors({});
    };

    return (
        <>
            <div className="space-y-6">
                <Heading
                    variant="small"
                    title="Delete account"
                    description="Delete your account and all of its resources"
                />
                <div className="space-y-4 rounded-lg border border-red-100 bg-red-50 p-4 dark:border-red-200/10 dark:bg-red-700/10">
                    <div className="relative space-y-0.5 text-red-600 dark:text-red-100">
                        <p className="font-medium">Warning</p>
                        <p className="text-sm">
                            Please proceed with caution, this cannot be undone.
                        </p>
                    </div>

                    <Dialog open={isOpen} onOpenChange={setIsOpen}>
                        <DialogTrigger asChild>
                            <Button
                                variant="destructive"
                                data-test="delete-user-button"
                            >
                                Delete account
                            </Button>
                        </DialogTrigger>
                        <DialogContent>
                            <DialogTitle>
                                Are you sure you want to delete your account?
                            </DialogTitle>
                            <DialogDescription>
                                Once your account is deleted, all of its resources
                                and data will also be permanently deleted. Please
                                enter your password to confirm you would like to
                                permanently delete your account.
                            </DialogDescription>

                            <form onSubmit={handleDelete} className="space-y-6">
                                <div className="grid gap-2">
                                    <Label
                                        htmlFor="password"
                                        className="sr-only"
                                    >
                                        Password
                                    </Label>

                                    <PasswordInput
                                        id="password"
                                        name="password"
                                        value={password}
                                        onChange={(e) => setPassword(e.target.value)}
                                        ref={passwordInput}
                                        placeholder="Password"
                                        autoComplete="current-password"
                                    />

                                    <InputError message={errors.password} />
                                </div>

                                <DialogFooter className="gap-2">
                                    <DialogClose asChild>
                                        <Button
                                            type="button"
                                            variant="secondary"
                                            onClick={resetAndClearErrors}
                                        >
                                            Cancel
                                        </Button>
                                    </DialogClose>

                                    <Button
                                        type="submit"
                                        variant="destructive"
                                        disabled={processing}
                                        data-test="confirm-delete-user-button"
                                    >
                                        {processing && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                                        Delete account
                                    </Button>
                                </DialogFooter>
                            </form>
                        </DialogContent>
                    </Dialog>
                </div>
            </div>

            {/* SUCCESS POP-UP MODAL */}
            {showSuccessModal && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-xs transition-opacity duration-300 animate-fadeIn">
                    <div className="w-full max-w-xs transform rounded-2xl bg-white p-6 text-center shadow-2xl transition-all duration-300 animate-scaleUp dark:bg-gray-900">
                        <div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-emerald-50 text-emerald-600 dark:bg-emerald-950">
                            <CheckCircle2 className="h-7 w-7" />
                        </div>
                        <h4 className="text-base font-bold text-gray-900 dark:text-gray-100">Account Deleted!</h4>
                        <p className="mt-1 text-xs text-gray-500 dark:text-gray-400">Redirecting...</p>
                    </div>
                </div>
            )}
        </>
    );
}