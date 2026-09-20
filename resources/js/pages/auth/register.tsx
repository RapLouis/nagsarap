import { useForm, Head, Link } from '@inertiajs/react';
import InputError from '@/components/input-error';
import PasswordInput from '@/components/password-input';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Spinner } from '@/components/ui/spinner';
import { validateFaceImage } from '@/lib/faceValidation';
import { compressImage } from '@/lib/utils';
import {
    Cpu,
    Mail,
    User,
    Hash,
    FileText,
    CheckCircle2,
    Upload,
} from 'lucide-react';
import { useState, FormEvent, ChangeEvent } from 'react';

type Props = {
    teamInvitation?: {
        code?: string;
    } | null;
};

const inputClass =
    'w-full rounded-lg border border-gray-300 bg-white text-black placeholder:text-gray-400 caret-[#1B1F5C] shadow-sm transition-colors focus-visible:border-[#F5A623] focus-visible:ring-1 focus-visible:ring-[#F5A623] focus-visible:outline-none';

const iconClass =
    'pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400';

export default function Register({}: Props) {
    const [form5Name, setForm5Name] = useState<string>('');
    const [photoName, setPhotoName] = useState<string>('');
    const [isValidatingPhoto, setIsValidatingPhoto] = useState<boolean>(false);

    const { data, setData, post, processing, errors, reset, setError, clearErrors } = useForm<{
        student_number: string;
        surname: string;
        firstname: string;
        middlename: string;
        ext: string;
        email: string;
        password: string;
        password_confirmation: string;
        profile_photo: File | null;
        form_5: File | null;
    }>({
        student_number: '',
        surname: '',
        firstname: '',
        middlename: '',
        ext: '',
        email: '',
        password: '',
        password_confirmation: '',
        profile_photo: null,
        form_5: null,
    });

    const formatStudentNumber = (value: string) => {
        let numbers = value.replace(/\D/g, '');
        numbers = numbers.slice(0, 8);

        if (numbers.length > 2) {
            numbers = numbers.slice(0, 2) + '-' + numbers.slice(2);
        }

        return numbers;
    };

    // =========================================================================
    // CLIENT-SIDE FACE VALIDATION & COMPRESSION HANDLER
    // =========================================================================
    const handleProfilePhotoChange = async (e: ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (!file) return;

        setIsValidatingPhoto(true);
        clearErrors('profile_photo');

        try {
            // 1. Run MediaPipe face quality checks (Blur, Face count, ratio)
            const result = await validateFaceImage(file);

            if (!result.isValid) {
                setError('profile_photo', result.message || 'Invalid face photo.');
                setData('profile_photo', null);
                setPhotoName('');
                e.target.value = ''; // Reset file input element
                setIsValidatingPhoto(false);
                return;
            }

            // 2. Compress & resize image to prevent memory spikes & optimize upload
            const compressedFile = await compressImage(file, 1000, 1000, 0.8);

            // 3. Set compressed file in state if checks pass
            setData('profile_photo', compressedFile);
            setPhotoName(file.name);
        } catch (error) {
            console.error('Face validation or compression error:', error);
            setError('profile_photo', 'Failed to process image. Please try another photo.');
            setData('profile_photo', null);
            setPhotoName('');
            e.target.value = '';
        } finally {
            setIsValidatingPhoto(false);
        }
    };

    const handleSubmit = (e: FormEvent) => {
        e.preventDefault();

        post('/register', {
            forceFormData: true, // <--- Required for binary PDF uploads
            onSuccess: () => reset('password', 'password_confirmation'),
        });
    };

    return (
        <div className="min-h-screen w-full bg-[#F5F6FA] font-sans">
            <Head title="Register" />

            <div className="flex min-h-screen flex-col lg:flex-row">
                {/* LEFT PANEL */}
                <div className="relative flex flex-1 items-center justify-center overflow-hidden bg-[#1B1F5C] p-8 text-center text-white lg:p-16">
                    <div
                        className="pointer-events-none absolute inset-0 opacity-15"
                        style={{
                            backgroundImage: `
                                radial-gradient(#F5A623 1.5px, transparent 1.5px),
                                linear-gradient(to right, rgba(255,255,255,0.08) 1px, transparent 1px),
                                linear-gradient(to bottom, rgba(255,255,255,0.08) 1px, transparent 1px)
                            `,
                            backgroundSize: '28px 28px, 28px 28px, 28px 28px',
                        }}
                    />
                    <div className="pointer-events-none absolute -left-20 -top-20 h-64 w-64 rounded-full border border-[#F5A623]/20" />
                    <div className="pointer-events-none absolute -bottom-32 -right-32 h-80 w-80 rounded-full border border-[#F5A623]/20" />

                    <div className="relative z-10">
                        <div className="mx-auto mb-6 flex h-24 w-24 items-center justify-center rounded-full border-4 border-[#F5A623] bg-white shadow-[0_0_25px_rgba(245,166,35,0.3)]">
                            <Cpu className="h-12 w-12 text-[#1B1F5C]" />
                        </div>
                        <h1 className="text-4xl font-extrabold tracking-wider text-[#F5A623]">CCIS</h1>
                        <h2 className="mt-1 text-xl font-bold tracking-wide">Attendance System</h2>
                        <p className="mx-auto mt-4 max-w-xs text-sm leading-relaxed text-white/70">
                            Create your student account, upload your profile picture, and verify your Form 5.
                        </p>
                        <div className="mx-auto mt-8 h-1 w-16 rounded-full bg-[#F5A623]" />
                    </div>
                </div>

                {/* RIGHT PANEL */}
                <div className="flex flex-1 items-center justify-center bg-[#F5F6FA] p-6 lg:p-12">
                    <div className="w-full max-w-lg rounded-2xl border border-gray-100 bg-white p-8 shadow-xl lg:p-9">
                        <div className="mb-7 text-center">
                            <h3 className="text-2xl font-bold text-[#1B1F5C]">Create Student Account</h3>
                            <p className="mt-2 text-xs text-gray-500">Fill in your information and attach required documents</p>
                        </div>

                        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
                            {/* STUDENT NUMBER */}
                            <div className="grid gap-2">
                                <Label htmlFor="student_number" className="text-xs font-semibold text-gray-700">
                                    Student Number <span className="ml-1 text-[#F5A623]">*</span>
                                </Label>
                                <div className="relative">
                                    <Hash className={iconClass} />
                                    <Input
                                        id="student_number"
                                        type="text"
                                        name="student_number"
                                        value={data.student_number}
                                        required
                                        autoFocus
                                        tabIndex={1}
                                        autoComplete="off"
                                        inputMode="numeric"
                                        maxLength={9}
                                        placeholder="e.g. 23-140040"
                                        pattern="[0-9]{2}-[0-9]{6}"
                                        onChange={(e) => {
                                            const formatted = formatStudentNumber(e.target.value);
                                            setData('student_number', formatted);
                                        }}
                                        className={`${inputClass} pl-9`}
                                    />
                                </div>
                                <p className="text-[11px] text-gray-400">Format: YY-NNNNNN (e.g. 23-140040)</p>
                                <InputError message={errors.student_number} />
                            </div>

                            {/* SURNAME + FIRST NAME */}
                            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                                <div className="grid gap-2">
                                    <Label htmlFor="surname" className="text-xs font-semibold text-gray-700">
                                        Surname <span className="ml-1 text-[#F5A623]">*</span>
                                    </Label>
                                    <div className="relative">
                                        <User className={iconClass} />
                                        <Input
                                            id="surname"
                                            type="text"
                                            name="surname"
                                            value={data.surname}
                                            required
                                            tabIndex={2}
                                            autoComplete="family-name"
                                            placeholder="Surname"
                                            onChange={(e) => setData('surname', e.target.value)}
                                            className={`${inputClass} pl-9`}
                                        />
                                    </div>
                                    <InputError message={errors.surname} />
                                </div>

                                <div className="grid gap-2">
                                    <Label htmlFor="firstname" className="text-xs font-semibold text-gray-700">
                                        First Name <span className="ml-1 text-[#F5A623]">*</span>
                                    </Label>
                                    <div className="relative">
                                        <User className={iconClass} />
                                        <Input
                                            id="firstname"
                                            type="text"
                                            name="firstname"
                                            value={data.firstname}
                                            required
                                            tabIndex={3}
                                            autoComplete="given-name"
                                            placeholder="First name"
                                            onChange={(e) => setData('firstname', e.target.value)}
                                            className={`${inputClass} pl-9`}
                                        />
                                    </div>
                                    <InputError message={errors.firstname} />
                                </div>
                            </div>

                            {/* MIDDLE NAME + EXTENSION */}
                            <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
                                <div className="grid gap-2 sm:col-span-2">
                                    <Label htmlFor="middlename" className="text-xs font-semibold text-gray-700">
                                        Middle Name
                                    </Label>
                                    <Input
                                        id="middlename"
                                        type="text"
                                        name="middlename"
                                        value={data.middlename}
                                        tabIndex={4}
                                        autoComplete="additional-name"
                                        placeholder="Middle name"
                                        onChange={(e) => setData('middlename', e.target.value)}
                                        className={inputClass}
                                    />
                                    <InputError message={errors.middlename} />
                                </div>

                                <div className="grid gap-2">
                                    <Label htmlFor="ext" className="text-xs font-semibold text-gray-700">
                                        Extension
                                    </Label>
                                    <Input
                                        id="ext"
                                        type="text"
                                        name="ext"
                                        value={data.ext}
                                        tabIndex={5}
                                        placeholder="Jr., Sr."
                                        onChange={(e) => setData('ext', e.target.value)}
                                        className={inputClass}
                                    />
                                    <InputError message={errors.ext} />
                                </div>
                            </div>

                            {/* EMAIL */}
                            <div className="grid gap-2">
                                <Label htmlFor="email" className="text-xs font-semibold text-gray-700">
                                    Email Address <span className="ml-1 text-[#F5A623]">*</span>
                                </Label>
                                <div className="relative">
                                    <Mail className={iconClass} />
                                    <Input
                                        id="email"
                                        type="email"
                                        name="email"
                                        value={data.email}
                                        required
                                        tabIndex={6}
                                        autoComplete="email"
                                        placeholder="Enter your email address"
                                        onChange={(e) => setData('email', e.target.value)}
                                        className={`${inputClass} pl-9`}
                                    />
                                </div>
                                <InputError message={errors.email} />
                            </div>

                            {/* PASSWORD */}
                            <div className="grid gap-2">
                                <Label htmlFor="password" className="text-xs font-semibold text-gray-700">
                                    Password <span className="ml-1 text-[#F5A623]">*</span>
                                </Label>
                                <PasswordInput
                                    id="password"
                                    name="password"
                                    value={data.password}
                                    required
                                    tabIndex={7}
                                    autoComplete="new-password"
                                    placeholder="Create a password"
                                    onChange={(e) => setData('password', e.target.value)}
                                    className={inputClass}
                                />
                                <InputError message={errors.password} />
                            </div>

                            {/* CONFIRM PASSWORD */}
                            <div className="grid gap-2">
                                <Label htmlFor="password_confirmation" className="text-xs font-semibold text-gray-700">
                                    Confirm Password <span className="ml-1 text-[#F5A623]">*</span>
                                </Label>
                                <PasswordInput
                                    id="password_confirmation"
                                    name="password_confirmation"
                                    value={data.password_confirmation}
                                    required
                                    tabIndex={8}
                                    autoComplete="new-password"
                                    placeholder="Confirm your password"
                                    onChange={(e) => setData('password_confirmation', e.target.value)}
                                    className={inputClass}
                                />
                                <InputError message={errors.password_confirmation} />
                            </div>

                            {/* PROFILE PHOTO UPLOAD */}
                            <div className="grid gap-2">
                                <Label htmlFor="profile_photo" className="text-xs font-semibold text-gray-700">
                                    Profile Picture <span className="ml-1 text-[#F5A623]">*</span>
                                </Label>
                                <label
                                    htmlFor="profile_photo"
                                    className="group flex cursor-pointer items-center gap-3 rounded-lg border border-dashed border-gray-300 bg-white px-4 py-3 transition-all hover:border-[#F5A623] hover:bg-[#FFFBF3]"
                                >
                                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-[#1B1F5C]/10 transition-colors group-hover:bg-[#F5A623]/20">
                                        {isValidatingPhoto ? (
                                            <Spinner className="h-4 w-4 text-[#1B1F5C]" />
                                        ) : photoName ? (
                                            <CheckCircle2 className="h-4 w-4 text-green-600" />
                                        ) : (
                                            <Upload className="h-4 w-4 text-[#1B1F5C]" />
                                        )}
                                    </div>
                                    <div className="min-w-0">
                                        <p className="text-sm font-medium text-gray-700 group-hover:text-[#1B1F5C]">
                                            {isValidatingPhoto
                                                ? 'Analyzing face quality...'
                                                : photoName || 'Upload Profile Picture'}
                                        </p>
                                        <p className="mt-0.5 text-xs text-gray-400">
                                            Clear, well-lit headshot (JPG, JPEG, PNG)
                                        </p>
                                    </div>
                                    <Input
                                        id="profile_photo"
                                        type="file"
                                        name="profile_photo"
                                        accept="image/jpeg,image/png,image/jpg"
                                        required
                                        disabled={isValidatingPhoto}
                                        tabIndex={9}
                                        className="hidden"
                                        onChange={handleProfilePhotoChange}
                                    />
                                </label>
                                <InputError message={errors.profile_photo} />
                            </div>

                            {/* FORM 5 UPLOAD FIELD */}
                            <div className="grid gap-2">
                                <Label htmlFor="form_5" className="text-xs font-semibold text-gray-700">
                                    Form 5 Document <span className="ml-1 text-[#F5A623]">*</span>
                                </Label>
                                <label
                                    htmlFor="form_5"
                                    className="group flex cursor-pointer items-center gap-3 rounded-lg border border-dashed border-gray-300 bg-white px-4 py-3 transition-all hover:border-[#F5A623] hover:bg-[#FFFBF3]"
                                >
                                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-[#1B1F5C]/10 transition-colors group-hover:bg-[#F5A623]/20">
                                        {form5Name ? (
                                            <CheckCircle2 className="h-4 w-4 text-green-600" />
                                        ) : (
                                            <FileText className="h-4 w-4 text-[#1B1F5C]" />
                                        )}
                                    </div>
                                    <div className="min-w-0">
                                        <p className="text-sm font-medium text-gray-700 group-hover:text-[#1B1F5C]">
                                            {form5Name || 'Upload Form 5 PDF'}
                                        </p>
                                        <p className="mt-0.5 text-xs text-gray-400">PDF document only (Max 10MB)</p>
                                    </div>
                                    <Input
                                        id="form_5"
                                        type="file"
                                        name="form_5"
                                        accept="application/pdf,.pdf"
                                        required
                                        tabIndex={10}
                                        className="hidden"
                                        onChange={(e) => {
                                            const file = e.target.files?.[0];
                                            if (file) {
                                                setData('form_5', file);
                                                setForm5Name(file.name);
                                            }
                                        }}
                                    />
                                </label>
                                <InputError message={errors.form_5} />
                            </div>

                            {/* SUBMIT BUTTON */}
                            <Button
                                type="submit"
                                disabled={processing || isValidatingPhoto || !data.form_5 || !data.profile_photo}
                                tabIndex={11}
                                className="mt-3 w-full rounded-lg bg-[#1B1F5C] py-2.5 font-medium text-white shadow-md transition-all hover:border-b-2 hover:border-[#F5A623] hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:ring-offset-2 disabled:opacity-50"
                            >
                                {processing && <Spinner className="mr-2" />}
                                Register & Verify Form 5 →
                            </Button>

                            {/* LOGIN LINK */}
                            <div className="mt-3 text-center text-xs text-gray-500">
                                Already have an account?{' '}
                                <Link
                                    href="/login"
                                    className="font-bold text-[#1B1F5C] transition-colors hover:text-[#F5A623]"
                                >
                                    Log in here
                                </Link>
                            </div>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    );
}

Register.layout = {
    title: 'Create an Account',
    description: 'Register for the CCIS Attendance System',
};