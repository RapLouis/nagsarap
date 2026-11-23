import { useForm, Head, Link } from '@inertiajs/react';
import InputError from '@/components/input-error';
import PasswordInput from '@/components/password-input';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Spinner } from '@/components/ui/spinner';
import {
    AlertCircle,
    Camera,
    Check,
    CheckCircle2,
    FileText,
    Hash,
    Info,
    Mail,
    RotateCcw,
    Shield,
    Trash2,
    User,
    X,
} from 'lucide-react';
import { useState, useRef, useEffect, FormEvent, DragEvent, KeyboardEvent } from 'react';
import {
    calculateYaw,
    describeCameraError,
    getPlacementIssue,
    getSharedLandmarker,
    measureBrightness,
    REFERENCE_CAPTURE_OPTIONS,
    REFERENCE_FRONTAL_YAW_MAX,
    REFERENCE_MAX_BRIGHTNESS,
    REFERENCE_MIN_BRIGHTNESS,
    REFERENCE_STABLE_FRAMES,
    VIDEO_CONSTRAINTS,
} from '@/lib/liveness';
import logoImage from '../logo.jpeg';

// Flat Design Input Base Styling with Accessible Focus Ring & Minimum Touch Target
const inputClass =
    'w-full min-h-[44px] rounded-lg border border-gray-300 bg-white text-gray-900 placeholder:text-gray-400 caret-[#1B1F5C] shadow-sm transition-all focus-visible:border-[#F5A623] focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none text-sm disabled:cursor-not-allowed disabled:bg-gray-100 disabled:opacity-75';

const iconClass =
    'pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400';

// -----------------------------------------------------------------------------
// Data Sanitization & Formatting Helpers
// -----------------------------------------------------------------------------

/** 1. Enforces digit-only input and auto-formats as YY-XXXXXX */
const formatStudentNumber = (value: string): string => {
    const digits = value.replace(/\D/g, '');
    if (digits.length <= 2) return digits;
    return `${digits.slice(0, 2)}-${digits.slice(2, 8)}`;
};

/** 2. Restricts input to letters, spaces, hyphens, and periods */
const sanitizeNameInput = (value: string): string => {
    return value.replace(/[^a-zA-Z\s.-]/g, '');
};

/** 3. Normalizes title-casing (e.g., "juan dela cruz" -> "Juan Dela Cruz") */
const formatTitleCase = (value: string): string => {
    if (!value) return '';
    return value
        .trim()
        .replace(/\s+/g, ' ')
        .toLowerCase()
        .replace(/(?:^|\s|-)\S/g, (match) => match.toUpperCase());
};

/** 4. Cleans and lowercases email input */
const sanitizeEmail = (value: string): string => {
    return value.trim().toLowerCase();
};

export default function Register() {
    const videoRef = useRef<HTMLVideoElement | null>(null);
    const modalRef = useRef<HTMLDivElement | null>(null);

    const [isCameraModalOpen, setIsCameraModalOpen] = useState(false);
    const [cameraActive, setCameraActive] = useState(false);
    const [capturedPreview, setCapturedPreview] = useState<string | null>(null);
    const [cameraError, setCameraError] = useState<string | null>(null);
    const [cameraHint, setCameraHint] = useState<string | null>(null);
    const [stableCount, setStableCount] = useState(0);

    const [isDragging, setIsDragging] = useState(false);
    const [form5File, setForm5File] = useState<File | null>(null);
    const [form5Error, setForm5Error] = useState<string | null>(null);

    const { data, setData, post, processing, errors, reset } = useForm<{
        student_number: string;
        surname: string;
        firstname: string;
        middlename: string;
        ext: string;
        email: string;
        password: string;
        password_confirmation: string;
        profile_photo: Blob | null;
        form_5: File | null;
        biometric_consent: boolean;
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
        biometric_consent: false,
    });

    const password = data.password || '';

    // Password requirements matching AppServiceProvider rules
    const passwordRequirements = [
        { label: 'At least 12 characters long', satisfied: password.length >= 12 },
        { label: 'Contains an uppercase letter (A-Z)', satisfied: /[A-Z]/.test(password) },
        { label: 'Contains a lowercase letter (a-z)', satisfied: /[a-z]/.test(password) },
        { label: 'Contains a number (0-9)', satisfied: /[0-9]/.test(password) },
        { label: 'Contains a special symbol (!@#$...)', satisfied: /[^A-Za-z0-9]/.test(password) },
    ];

    const isPasswordValid = passwordRequirements.every((req) => req.satisfied);
    const passwordMismatch =
        data.password_confirmation.length > 0 && data.password !== data.password_confirmation;

    // -------------------------------------------------------------------------
    // Camera Stream Management & Hardware Cleanup
    // -------------------------------------------------------------------------
    const startCamera = async () => {
        try {
            const stream = await navigator.mediaDevices.getUserMedia(VIDEO_CONSTRAINTS);
            if (videoRef.current) {
                videoRef.current.srcObject = stream;
                await videoRef.current.play().catch(() => {});
                setCameraActive(true);
                setCameraError(null);
            }
        } catch (err) {
            setCameraError(describeCameraError(err));
            setCameraActive(false);
        }
    };

    const stopCamera = () => {
        if (videoRef.current && videoRef.current.srcObject) {
            const stream = videoRef.current.srcObject as MediaStream;
            stream.getTracks().forEach((track) => track.stop());
            videoRef.current.srcObject = null;
        }
        setCameraActive(false);
        setStableCount(0);
    };

    const handleCloseModal = () => {
        stopCamera();
        setIsCameraModalOpen(false);
    };

    useEffect(() => {
        if (isCameraModalOpen) {
            startCamera();
        } else {
            stopCamera();
        }
        return () => stopCamera();
    }, [isCameraModalOpen]);

    // Accessibility Keyboard Shortcut: Close modal on Escape key
    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent | globalThis.KeyboardEvent) => {
            if (e.key === 'Escape' && isCameraModalOpen) {
                handleCloseModal();
            }
        };
        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [isCameraModalOpen]);

    useEffect(() => {
        if (!cameraActive || !isCameraModalOpen) return;

        let active = true;
        let animationId: number;

        const checkQuality = async () => {
            const video = videoRef.current;
            if (video && video.readyState >= 2) {
                const brightness = measureBrightness(video);
                if (brightness !== null) {
                    if (brightness < REFERENCE_MIN_BRIGHTNESS) {
                        setCameraHint('Lighting is too dark. Please increase light source.');
                        setStableCount(0);
                        if (active) animationId = requestAnimationFrame(checkQuality);
                        return;
                    }
                    if (brightness > REFERENCE_MAX_BRIGHTNESS) {
                        setCameraHint('Lighting is too bright or backlit.');
                        setStableCount(0);
                        if (active) animationId = requestAnimationFrame(checkQuality);
                        return;
                    }
                }

                try {
                    const landmarker = await getSharedLandmarker();
                    const result = landmarker.detectForVideo(video, performance.now());
                    const faces = result.faceLandmarks ?? [];

                    if (faces.length === 0) {
                        setCameraHint('Position your face inside the guide circle.');
                        setStableCount(0);
                    } else if (faces.length > 1) {
                        setCameraHint('Multiple faces detected. Ensure only you are in frame.');
                        setStableCount(0);
                    } else {
                        const landmarks = faces[0];
                        const placement = getPlacementIssue(landmarks);
                        const yaw = calculateYaw(landmarks);

                        if (placement) {
                            setCameraHint(placement);
                            setStableCount(0);
                        } else if (Math.abs(yaw) > REFERENCE_FRONTAL_YAW_MAX) {
                            setCameraHint('Look directly straight at the camera.');
                            setStableCount(0);
                        } else {
                            setCameraHint(null);
                            setStableCount((prev) => Math.min(prev + 1, REFERENCE_STABLE_FRAMES));
                        }
                    }
                } catch {
                    setCameraHint(null);
                }
            }
            if (active) animationId = requestAnimationFrame(checkQuality);
        };

        animationId = requestAnimationFrame(checkQuality);
        return () => {
            active = false;
            cancelAnimationFrame(animationId);
        };
    }, [cameraActive, isCameraModalOpen]);

    const handleCaptureUninvertedSelfie = async () => {
        const video = videoRef.current;
        if (!video) return;

        const { maxSide = 1280, quality = 0.92 } = REFERENCE_CAPTURE_OPTIONS;
        const sourceWidth = video.videoWidth || 640;
        const sourceHeight = video.videoHeight || 480;
        const scale = Math.min(1, maxSide / Math.max(sourceWidth, sourceHeight));

        const canvas = document.createElement('canvas');
        canvas.width = Math.round(sourceWidth * scale);
        canvas.height = Math.round(sourceHeight * scale);

        const context = canvas.getContext('2d', { alpha: false });
        if (!context) return;

        context.translate(canvas.width, 0);
        context.scale(-1, 1);
        context.drawImage(video, 0, 0, canvas.width, canvas.height);

        canvas.toBlob(
            (blob) => {
                if (blob) {
                    setData('profile_photo', blob);
                    setCapturedPreview(URL.createObjectURL(blob));
                    stopCamera();
                    setIsCameraModalOpen(false);
                }
            },
            'image/jpeg',
            quality
        );
    };

    const handleRetakeSelfie = () => {
        if (capturedPreview) URL.revokeObjectURL(capturedPreview);
        setCapturedPreview(null);
        setData('profile_photo', null);
        setStableCount(0);
        setIsCameraModalOpen(true);
    };

    // -------------------------------------------------------------------------
    // Form 5 PDF File Upload Handlers & Validation
    // -------------------------------------------------------------------------
    const handlePdfSelect = (file: File) => {
        setForm5Error(null);
        if (file.type !== 'application/pdf') {
            setForm5Error('Invalid file format. Please upload an official PDF document.');
            return;
        }
        if (file.size > 10 * 1024 * 1024) {
            setForm5Error('File size exceeds the 10MB limit.');
            return;
        }
        setForm5File(file);
        setData('form_5', file);
    };

    const handleDropPdf = (e: DragEvent<HTMLDivElement>) => {
        e.preventDefault();
        setIsDragging(false);
        const file = e.dataTransfer.files?.[0];
        if (file) handlePdfSelect(file);
    };

    const handleRemovePdf = () => {
        setForm5File(null);
        setData('form_5', null);
        setForm5Error(null);
    };

    // -------------------------------------------------------------------------
    // Submit Handler with Final Data Sanitization
    // -------------------------------------------------------------------------
    const handleSubmit = (e: FormEvent) => {
        e.preventDefault();

        if (data.password !== data.password_confirmation || !isPasswordValid) {
            return;
        }

        // Final data sanitization sweep prior to posting payload
        setData((prev) => ({
            ...prev,
            student_number: formatStudentNumber(prev.student_number),
            email: sanitizeEmail(prev.email),
            surname: formatTitleCase(prev.surname),
            firstname: formatTitleCase(prev.firstname),
            middlename: formatTitleCase(prev.middlename),
            ext: prev.ext.trim(),
        }));

        post('/register', {
            forceFormData: true,
            onSuccess: () => reset('password', 'password_confirmation'),
        });
    };

    const isSelfieReady = stableCount >= REFERENCE_STABLE_FRAMES;
    const stabilityProgress = Math.round((stableCount / REFERENCE_STABLE_FRAMES) * 100);

    return (
        <div className="min-h-screen w-full bg-[#F5F6FA] font-sans text-gray-900 antialiased">
            <Head title="Register Account | 4ttnd Attendance System" />

            <div className="flex min-h-screen flex-col lg:h-screen lg:flex-row lg:overflow-hidden">
                {/* LEFT BRANDING PANEL */}
                <aside className="relative flex flex-col items-center justify-center overflow-hidden bg-[#1B1F5C] p-8 text-center text-white shrink-0 lg:w-5/12 lg:h-screen lg:p-16">
                    <div className="relative z-10 my-auto flex flex-col items-center">
                        <div className="mx-auto mb-6 flex h-24 w-24 items-center justify-center overflow-hidden rounded-full border-4 border-[#F5A623] bg-white p-2 shadow-xl ring-4 ring-white/10">
                            <img
                                src={logoImage}
                                alt="4ttnd System Logo"
                                className="h-full w-full scale-125 object-contain"
                            />
                        </div>
                        <h1 className="text-4xl font-black tracking-tight text-[#F5A623] sm:text-5xl">
                            4ttnd
                        </h1>
                        <h2 className="mt-1 text-xl font-bold tracking-wide text-white/95 sm:text-2xl">
                            Attendance System
                        </h2>
                        <p className="mx-auto mt-4 max-w-sm text-sm leading-relaxed text-white/80">
                            Create your verified student account, complete biometric setup, and upload your institutional Form 5 document.
                        </p>
                    </div>

                    <div className="mt-8 text-xs text-white/50">
                        © {new Date().getFullYear()} Mariano Marcos State University
                    </div>
                </aside>

                {/* RIGHT FORM PANEL */}
                <div className="flex flex-1 items-center justify-center bg-[#F5F6FA] p-4 sm:p-8 lg:w-7/12 lg:h-screen lg:overflow-y-auto lg:p-12">
                    <main className="w-full max-w-2xl rounded-2xl border border-gray-200/80 bg-white p-6 shadow-xl sm:p-10 my-auto">
                        <header className="mb-8 text-center sm:text-left">
                            <h3 className="text-2xl font-black tracking-tight text-[#1B1F5C] sm:text-3xl">
                                Student Registration
                            </h3>
                            <p className="mt-1 text-xs sm:text-sm font-medium text-gray-500">
                                Please fill in your official details to setup biometric liveness verification
                            </p>
                        </header>

                        <form onSubmit={handleSubmit} noValidate className="flex flex-col gap-6">
                            {/* SECTION 1: PERSONAL DETAILS (Refined Layout Sequence: Last Name/Middle Name & First Name/Suffix) */}
                            <fieldset className="flex flex-col gap-4 rounded-xl border border-gray-200 bg-gray-50/60 p-4 sm:p-5">
                                <legend className="px-2 text-xs font-bold uppercase tracking-wider text-[#1B1F5C]">
                                    1. Personal Details
                                </legend>

                                {/* Row 1: Last Name (Wider) and Middle Name (Short) */}
                                <div className="grid grid-cols-1 gap-4 sm:grid-cols-3 items-start">
                                    <div className="grid gap-1.5 sm:col-span-2">
                                        <Label htmlFor="surname" className="text-xs font-semibold text-gray-700">
                                            Surname / Last Name <span className="text-red-500" aria-hidden="true">*</span>
                                        </Label>
                                        <div className="relative">
                                            <User className={iconClass} />
                                            <Input
                                                id="surname"
                                                type="text"
                                                value={data.surname}
                                                required
                                                aria-required="true"
                                                aria-invalid={!!errors.surname}
                                                placeholder="Dela Cruz"
                                                onChange={(e) => setData('surname', sanitizeNameInput(e.target.value))}
                                                onBlur={(e) => setData('surname', formatTitleCase(e.target.value))}
                                                className={`${inputClass} pl-9`}
                                            />
                                        </div>
                                        <InputError message={errors.surname} />
                                    </div>

                                    <div className="grid gap-1.5 sm:col-span-1">
                                        <Label htmlFor="middlename" className="text-xs font-semibold text-gray-700">
                                            Middle Name <span className="text-gray-400 font-normal">(Optional)</span>
                                        </Label>
                                        <Input
                                            id="middlename"
                                            type="text"
                                            value={data.middlename}
                                            placeholder="Santos"
                                            onChange={(e) => setData('middlename', sanitizeNameInput(e.target.value))}
                                            onBlur={(e) => setData('middlename', formatTitleCase(e.target.value))}
                                            className={inputClass}
                                        />
                                        <InputError message={errors.middlename} />
                                    </div>
                                </div>

                                {/* Row 2: First Name (Wider) and Suffix (Short) */}
                                <div className="grid grid-cols-1 gap-4 sm:grid-cols-3 items-start">
                                    <div className="grid gap-1.5 sm:col-span-2">
                                        <Label htmlFor="firstname" className="text-xs font-semibold text-gray-700">
                                            First Name <span className="text-red-500" aria-hidden="true">*</span>
                                        </Label>
                                        <div className="relative">
                                            <User className={iconClass} />
                                            <Input
                                                id="firstname"
                                                type="text"
                                                value={data.firstname}
                                                required
                                                aria-required="true"
                                                aria-invalid={!!errors.firstname}
                                                placeholder="Juan"
                                                onChange={(e) => setData('firstname', sanitizeNameInput(e.target.value))}
                                                onBlur={(e) => setData('firstname', formatTitleCase(e.target.value))}
                                                className={`${inputClass} pl-9`}
                                            />
                                        </div>
                                        <InputError message={errors.firstname} />
                                    </div>

                                    <div className="grid gap-1.5 sm:col-span-1">
                                        <Label htmlFor="ext" className="text-xs font-semibold text-gray-700">
                                            Suffix <span className="text-gray-400 font-normal">(Optional)</span>
                                        </Label>
                                        <Input
                                            id="ext"
                                            type="text"
                                            value={data.ext}
                                            placeholder="Jr., III"
                                            onChange={(e) => setData('ext', sanitizeNameInput(e.target.value))}
                                            className={inputClass}
                                        />
                                        <InputError message={errors.ext} />
                                    </div>
                                </div>
                            </fieldset>

                            {/* SECTION 2: STUDENT CREDENTIALS */}
                            <fieldset className="flex flex-col gap-4 rounded-xl border border-gray-200 bg-gray-50/60 p-4 sm:p-5">
                                <legend className="px-2 text-xs font-bold uppercase tracking-wider text-[#1B1F5C]">
                                    2. Student Credentials
                                </legend>

                                {/* Row 1: Student Number & Email */}
                                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 items-start">
                                    <div className="grid gap-1.5">
                                        <Label htmlFor="student_number" className="text-xs font-semibold text-gray-700">
                                            Student Number <span className="text-red-500" aria-hidden="true">*</span>
                                        </Label>
                                        <div className="relative">
                                            <Hash className={iconClass} />
                                            <Input
                                                id="student_number"
                                                type="text"
                                                value={data.student_number}
                                                required
                                                aria-required="true"
                                                aria-invalid={!!errors.student_number}
                                                maxLength={9}
                                                placeholder="00-123456"
                                                onChange={(e) => setData('student_number', formatStudentNumber(e.target.value))}
                                                className={`${inputClass} pl-9`}
                                            />
                                        </div>
                                        <InputError message={errors.student_number} />
                                    </div>

                                    <div className="grid gap-1.5">
                                        <Label htmlFor="email" className="text-xs font-semibold text-gray-700">
                                            Email Address <span className="text-red-500" aria-hidden="true">*</span>
                                        </Label>
                                        <div className="relative">
                                            <Mail className={iconClass} />
                                            <Input
                                                id="email"
                                                type="email"
                                                value={data.email}
                                                required
                                                aria-required="true"
                                                aria-invalid={!!errors.email}
                                                placeholder="student@gmail.com"
                                                onChange={(e) => setData('email', sanitizeEmail(e.target.value))}
                                                className={`${inputClass} pl-9`}
                                            />
                                        </div>
                                        <InputError message={errors.email} />
                                    </div>
                                </div>

                                {/* Row 2: Passwords, Real-time Checklist, and Visual Error States */}
                                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 items-start">
                                    <div className="grid gap-1.5">
                                        <Label htmlFor="password" className="text-xs font-semibold text-gray-700">
                                            Password <span className="text-red-500" aria-hidden="true">*</span>
                                        </Label>
                                        <PasswordInput
                                            id="password"
                                            value={data.password}
                                            required
                                            aria-required="true"
                                            aria-invalid={!!errors.password || (password.length > 0 && !isPasswordValid)}
                                            placeholder="••••••••"
                                            onChange={(e) => setData('password', e.target.value)}
                                            className={`${inputClass} ${password.length > 0 && !isPasswordValid ? 'border-red-500 ring-2 ring-red-100' : ''}`}
                                        />

                                        {/* Real-time Password Checklist */}
                                        {password.length > 0 && (
                                            <ul className="mt-2 space-y-1.5 bg-white p-3 rounded-xl border border-gray-200 text-xs shadow-2xs animate-fadeIn">
                                                {passwordRequirements.map((req, index) => (
                                                    <li key={index} className="flex items-center gap-2">
                                                        <span
                                                            className={`flex h-4 w-4 shrink-0 items-center justify-center rounded-full text-[10px] font-bold transition-colors ${
                                                                req.satisfied
                                                                    ? 'bg-emerald-100 text-emerald-700'
                                                                    : 'bg-gray-100 text-gray-400'
                                                            }`}
                                                        >
                                                            {req.satisfied ? <Check className="h-3 w-3" /> : '•'}
                                                        </span>
                                                        <span
                                                            className={`transition-colors ${
                                                                req.satisfied
                                                                    ? 'text-emerald-800 font-semibold line-through opacity-75'
                                                                    : 'text-gray-500'
                                                            }`}
                                                        >
                                                            {req.label}
                                                        </span>
                                                    </li>
                                                ))}
                                            </ul>
                                        )}

                                        <InputError message={errors.password} />
                                    </div>

                                    <div className="grid gap-1.5">
                                        <Label htmlFor="password_confirmation" className="text-xs font-semibold text-gray-700">
                                            Confirm Password <span className="text-red-500" aria-hidden="true">*</span>
                                        </Label>
                                        <PasswordInput
                                            id="password_confirmation"
                                            value={data.password_confirmation}
                                            required
                                            aria-required="true"
                                            aria-invalid={passwordMismatch || !!errors.password_confirmation}
                                            placeholder="••••••••"
                                            onChange={(e) => setData('password_confirmation', e.target.value)}
                                            className={`${inputClass} ${passwordMismatch ? 'border-red-500 ring-2 ring-red-100' : ''}`}
                                        />
                                        {/* Stable error container height to prevent layout box jumping */}
                                        <div className="min-h-[20px]">
                                            {passwordMismatch ? (
                                                <p className="text-xs font-medium text-red-600 flex items-center gap-1">
                                                    <AlertCircle className="h-3.5 w-3.5" /> Passwords do not match
                                                </p>
                                            ) : (
                                                <InputError message={errors.password_confirmation} />
                                            )}
                                        </div>
                                    </div>
                                </div>
                            </fieldset>

                            {/* SECTION 3: BIOMETRICS & VERIFICATION FILES */}
                            <fieldset className="flex flex-col gap-4 rounded-xl border border-gray-200 bg-gray-50/60 p-4 sm:p-5">
                                <legend className="px-2 text-xs font-bold uppercase tracking-wider text-[#1B1F5C]">
                                    3. Biometrics & Documents
                                </legend>

                                {/* PROFILE SELFIE CAPTURE */}
                                <div className="grid gap-2">
                                    <Label className="text-xs font-semibold text-gray-700">
                                        Dashboard Profile Photo <span className="text-red-500" aria-hidden="true">*</span>
                                    </Label>
                                    <div className="flex flex-col sm:flex-row items-center gap-4 rounded-xl border border-gray-200 bg-white p-4 shadow-sm">
                                        <div className="relative flex h-24 w-24 shrink-0 items-center justify-center overflow-hidden rounded-full border-2 border-[#1B1F5C] bg-gray-100 shadow-inner">
                                            {capturedPreview ? (
                                                <img
                                                    src={capturedPreview}
                                                    alt="Captured profile selfie preview"
                                                    className="h-full w-full object-cover"
                                                />
                                            ) : (
                                                <Camera className="h-8 w-8 text-gray-400" aria-hidden="true" />
                                            )}
                                        </div>

                                        <div className="flex flex-col gap-2 text-center sm:text-left">
                                            <div>
                                                <p className="text-xs font-bold text-gray-800">
                                                    {capturedPreview ? 'Selfie Captured Successfully' : 'Frontal Face Selfie Required'}
                                                </p>
                                                <p className="text-[11px] text-gray-500 leading-normal mt-0.5">
                                                    Used as your primary baseline for biometric liveness matching.
                                                </p>
                                            </div>

                                            <div>
                                                {!capturedPreview ? (
                                                    <Button
                                                        type="button"
                                                        onClick={() => setIsCameraModalOpen(true)}
                                                        className="bg-[#1B1F5C] text-white hover:bg-[#131644] text-xs h-9 px-4 font-semibold shadow-sm focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                    >
                                                        <Camera className="mr-2 h-4 w-4" aria-hidden="true" /> Open Camera Modal
                                                    </Button>
                                                ) : (
                                                    <Button
                                                        type="button"
                                                        onClick={handleRetakeSelfie}
                                                        className="border-2 border-[#1B1F5C] bg-transparent text-[#1B1F5C] hover:bg-[#1B1F5C] hover:text-white transition-colors text-xs h-9 px-4 font-semibold focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                    >
                                                        <RotateCcw className="mr-2 h-4 w-4" aria-hidden="true" /> Retake Photo
                                                    </Button>
                                                )}
                                            </div>
                                        </div>
                                    </div>
                                    <InputError message={errors.profile_photo} />
                                </div>

                                {/* FORM 5 PDF UPLOAD */}
                                <div className="grid gap-2">
                                    <Label className="text-xs font-semibold text-gray-700">
                                        Upload Form 5 (PDF) <span className="text-red-500" aria-hidden="true">*</span>
                                    </Label>
                                    {!form5File ? (
                                        <div
                                            role="button"
                                            tabIndex={0}
                                            aria-label="Upload Form 5 PDF document"
                                            onClick={() => document.getElementById('form_5_file_input')?.click()}
                                            onKeyDown={(e) => {
                                                if (e.key === 'Enter' || e.key === ' ') {
                                                    e.preventDefault();
                                                    document.getElementById('form_5_file_input')?.click();
                                                }
                                            }}
                                            onDragOver={(e) => {
                                                e.preventDefault();
                                                setIsDragging(true);
                                            }}
                                            onDragLeave={() => setIsDragging(false)}
                                            onDrop={handleDropPdf}
                                            className={`flex cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed p-6 transition-all focus-visible:ring-2 focus-visible:ring-[#F5A623] focus-visible:outline-none ${
                                                isDragging
                                                    ? 'border-[#F5A623] bg-[#FFFBF3] scale-[0.99]'
                                                    : 'border-gray-300 bg-white hover:border-[#1B1F5C] hover:bg-gray-50/80'
                                            }`}
                                        >
                                            <FileText className="h-8 w-8 text-[#1B1F5C]" aria-hidden="true" />
                                            <p className="mt-2 text-xs font-medium text-gray-700 text-center">
                                                Drag and drop your Form 5 PDF here, or{' '}
                                                <span className="font-bold text-[#1B1F5C] underline">browse file</span>
                                            </p>
                                            <p className="mt-1 text-[11px] text-gray-400">PDF document only (Maximum 10MB)</p>
                                            <input
                                                type="file"
                                                accept="application/pdf"
                                                className="hidden"
                                                id="form_5_file_input"
                                                onChange={(e) => {
                                                    const file = e.target.files?.[0];
                                                    if (file) handlePdfSelect(file);
                                                }}
                                            />
                                        </div>
                                    ) : (
                                        <div className="flex items-center justify-between rounded-xl border border-green-200 bg-green-50/70 p-3.5 text-xs shadow-sm">
                                            <div className="flex items-center gap-3 overflow-hidden">
                                                <CheckCircle2 className="h-5 w-5 shrink-0 text-green-600" aria-hidden="true" />
                                                <div className="truncate">
                                                    <p className="font-semibold text-gray-900 truncate">{form5File.name}</p>
                                                    <p className="text-[10px] text-gray-500 font-medium">
                                                        {(form5File.size / (1024 * 1024)).toFixed(2)} MB • PDF Document
                                                    </p>
                                                </div>
                                            </div>
                                            <Button
                                                type="button"
                                                variant="ghost"
                                                size="sm"
                                                onClick={handleRemovePdf}
                                                aria-label="Remove uploaded Form 5 file"
                                                className="h-8 w-8 p-0 text-gray-500 hover:text-red-600 hover:bg-red-50 rounded-lg"
                                            >
                                                <Trash2 className="h-4 w-4" />
                                            </Button>
                                        </div>
                                    )}
                                    {form5Error && (
                                        <p className="text-xs font-medium text-red-600 flex items-center gap-1 mt-1">
                                            <AlertCircle className="h-3.5 w-3.5" /> {form5Error}
                                        </p>
                                    )}
                                    <InputError message={errors.form_5} />
                                </div>
                            </fieldset>

                            {/* CONSENT CHECKBOX */}
                            <div className="rounded-xl border border-gray-200 bg-gray-50/90 p-4">
                                <div className="flex items-start gap-3">
                                    <input
                                        type="checkbox"
                                        required
                                        id="consent_checkbox"
                                        aria-required="true"
                                        checked={data.biometric_consent}
                                        onChange={(e) => setData('biometric_consent', e.target.checked)}
                                        className="mt-0.5 h-4 w-4 rounded border-gray-300 text-[#1B1F5C] focus:ring-[#F5A623] cursor-pointer"
                                    />
                                    <label htmlFor="consent_checkbox" className="text-xs text-gray-700 leading-normal cursor-pointer select-none">
                                        <span className="font-bold text-gray-900">Biometric & Document Consent:</span> I grant permission to 
                                        capture, process, and store my facial biometric details and Form 5 documentation for academic verification and attendance checking.
                                    </label>
                                </div>
                            </div>

                            {/* SUBMIT BUTTON */}
                            <Button
                                type="submit"
                                disabled={
                                    processing ||
                                    !data.profile_photo ||
                                    !data.form_5 ||
                                    !data.biometric_consent ||
                                    passwordMismatch ||
                                    !isPasswordValid
                                }
                                className="w-full min-h-[48px] bg-[#1B1F5C] py-3 text-sm font-bold text-white shadow-lg hover:bg-[#131644] focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                            >
                                {processing ? (
                                    <>
                                        <Spinner className="mr-2 h-4 w-4" /> Processing Documents & Account...
                                    </>
                                ) : (
                                    'Complete Registration & Proceed to Liveness →'
                                )}
                            </Button>

                            <div className="text-center text-xs text-gray-600 pt-2">
                                Already registered?{' '}
                                <Link
                                    href="/login"
                                    className="font-bold text-[#1B1F5C] hover:underline focus-visible:ring-2 focus-visible:ring-[#F5A623] rounded-sm px-1"
                                >
                                    Log in here
                                </Link>
                            </div>
                        </form>
                    </main>
                </div>
            </div>

            {/* CAMERA MODAL DIALOG */}
            {isCameraModalOpen && (
                <div
                    role="dialog"
                    aria-modal="true"
                    aria-labelledby="modal_title"
                    onClick={handleCloseModal}
                    className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4 backdrop-blur-sm animate-in fade-in duration-200"
                >
                    <div
                        ref={modalRef}
                        onClick={(e) => e.stopPropagation()}
                        className="relative flex w-full max-w-md flex-col items-center rounded-2xl bg-white p-6 shadow-2xl border border-gray-100"
                    >
                        <button
                            type="button"
                            onClick={handleCloseModal}
                            aria-label="Close camera dialog"
                            className="absolute right-4 top-4 text-gray-400 hover:text-gray-700 p-1 rounded-lg focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                        >
                            <X className="h-5 w-5" />
                        </button>

                        <div className="flex items-center gap-2 text-[#1B1F5C]">
                            <Shield className="h-5 w-5 text-[#F5A623]" aria-hidden="true" />
                            <h3 id="modal_title" className="text-lg font-bold">Take Dashboard Selfie</h3>
                        </div>
                        <p className="mt-1 text-center text-xs text-gray-500">
                            Position your face inside the circle. Capture unlocks when alignment stabilizes.
                        </p>

                        <div className="relative mx-auto my-5 h-56 w-56 overflow-hidden rounded-full border-4 border-[#1B1F5C] bg-black shadow-inner">
                            <video
                                ref={videoRef}
                                autoPlay
                                playsInline
                                muted
                                className="h-full w-full scale-x-[-1] object-cover"
                            />
                            <div
                                className={`pointer-events-none absolute inset-2 rounded-full border-2 border-dashed transition-colors ${
                                    isSelfieReady ? 'border-green-500 border-4' : 'border-[#F5A623]'
                                }`}
                            />
                        </div>

                        <div className="w-full max-w-xs mb-2">
                            <div className="flex justify-between text-[11px] font-semibold text-gray-600 mb-1">
                                <span>Alignment Stability</span>
                                <span>{stabilityProgress}%</span>
                            </div>
                            <div className="h-2 w-full rounded-full bg-gray-200 overflow-hidden">
                                <div
                                    className="h-full bg-green-500 transition-all duration-200"
                                    style={{ width: `${stabilityProgress}%` }}
                                />
                            </div>
                        </div>

                        <div aria-live="polite" className="min-h-[24px] flex items-center justify-center">
                            {cameraHint && (
                                <p className="text-center text-xs text-amber-700 font-semibold bg-amber-50 px-3 py-1 rounded-md border border-amber-200 flex items-center gap-1.5">
                                    <Info className="h-3.5 w-3.5 shrink-0 text-amber-600" /> {cameraHint}
                                </p>
                            )}
                            {cameraError && (
                                <p className="text-center text-xs text-red-600 font-semibold bg-red-50 px-3 py-1 rounded-md border border-red-200 flex items-center gap-1.5">
                                    <AlertCircle className="h-3.5 w-3.5 shrink-0 text-red-600" /> {cameraError}
                                </p>
                            )}
                        </div>

                        <div className="mt-4 flex w-full gap-3">
                            <Button
                                type="button"
                                onClick={handleCloseModal}
                                className="flex-1 min-h-[40px] border border-gray-300 bg-white text-xs font-semibold text-gray-700 hover:border-red-600 hover:bg-red-50 hover:text-red-600 transition-colors focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            >
                                Cancel
                            </Button>
                            <Button
                                type="button"
                                onClick={handleCaptureUninvertedSelfie}
                                disabled={!cameraActive || !isSelfieReady}
                                className="flex-1 min-h-[40px] bg-[#1B1F5C] text-xs font-bold text-white hover:bg-[#131644] active:bg-[#0E1033] disabled:bg-gray-300 disabled:text-gray-500 disabled:opacity-70 transition-colors focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            >
                                <Camera className="mr-2 h-4 w-4" aria-hidden="true" /> Capture Photo
                            </Button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}