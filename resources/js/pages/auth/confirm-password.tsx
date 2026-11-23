import { Form, Head } from '@inertiajs/react';
import {
    index as confirmOptions,
    store as confirmStore,
} from '@/actions/Laravel/Passkeys/Http/Controllers/PasskeyConfirmationController';
import Heading from '@/components/heading';
import InputError from '@/components/input-error';
import PasskeyVerify from '@/components/passkey-verify';
import PasswordInput from '@/components/password-input';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { Spinner } from '@/components/ui/spinner';
import SettingsLayout from '@/layouts/settings/layout';
import { store } from '@/routes/password/confirm';
import { ShieldCheck } from 'lucide-react';

const inputClass =
    'w-full min-h-[44px] rounded-lg border border-gray-300 bg-white text-gray-900 placeholder:text-gray-400 caret-[#1B1F5C] shadow-sm transition-all focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none text-sm disabled:cursor-not-allowed disabled:bg-gray-100 disabled:opacity-75';

export default function ConfirmPassword() {
    return (
        <>
            <Head title="Confirm password" />

            <div className="space-y-6">
                <div className="flex items-center gap-2 border-b border-gray-100 pb-4">
                    <ShieldCheck className="h-5 w-5 text-[#1B1F5C]" aria-hidden="true" />
                    <Heading
                        variant="small"
                        title="Confirm password"
                        description="This is a secure area of the application. Please confirm your password before continuing."
                    />
                </div>

                <PasskeyVerify
                    routes={{
                        options: confirmOptions(),
                        submit: confirmStore(),
                    }}
                    label="Confirm with passkey"
                    loadingLabel="Confirming..."
                    separator="Or confirm with password"
                />

                <Form
                    {...store.form()}
                    resetOnSuccess={['password']}
                    noValidate
                    className="flex flex-col gap-5 pt-2"
                >
                    {({ processing, errors }) => (
                        <>
                            <div className="grid gap-1.5 max-w-md">
                                <Label htmlFor="password" className="text-xs font-semibold text-gray-700">
                                    Password <span className="text-red-500" aria-hidden="true">*</span>
                                </Label>
                                <PasswordInput
                                    id="password"
                                    name="password"
                                    required
                                    aria-required="true"
                                    aria-invalid={!!errors.password}
                                    aria-describedby={errors.password ? 'password_error' : undefined}
                                    placeholder="••••••••"
                                    autoComplete="current-password"
                                    autoFocus
                                    className={inputClass}
                                />
                                <InputError id="password_error" message={errors.password} />
                            </div>

                            <div className="flex items-center gap-4 pt-2">
                                <Button
                                    type="submit"
                                    disabled={processing}
                                    data-test="confirm-password-button"
                                    className="min-h-[44px] bg-[#1B1F5C] px-6 text-xs font-bold text-white shadow-md hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-50 transition-all"
                                >
                                    {processing ? (
                                        <>
                                            <Spinner className="mr-2 h-4 w-4" /> Confirming...
                                        </>
                                    ) : (
                                        'Confirm Password →'
                                    )}
                                </Button>
                            </div>
                        </>
                    )}
                </Form>
            </div>
        </>
    );
}

// Layout persistent wrapper targeting Settings Layout
ConfirmPassword.layout = (page: React.ReactNode) => (
    <SettingsLayout>{page}</SettingsLayout>
);