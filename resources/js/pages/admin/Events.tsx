import React, { useEffect, useRef, useState } from 'react';
import { Head, Link, router, useForm } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import DeleteModal from '@/components/delete-modal';
import LocationPicker from '@/components/location-picker';
import FormSwitch from '@/components/ui/form-switch';
import { formatAMPM } from '@/lib/timeUtils';
import {
    Calendar,
    MapPin,
    Plus,
    Search,
    Trash2,
    CheckCircle2,
    AlertCircle,
    X,
    LogIn,
    LogOut,
    Pencil,
    Check,
    XCircle,
    CalendarX,
    Navigation,
    Hexagon,
    CircleDot,
    Loader2,
    ArrowRight,
    ArrowLeft,
    FileText,
    Copy,
    Building2,
    CheckSquare,
    Square,
    Sun,
    Sunset,
    RotateCcw,
} from 'lucide-react';
import {
    validateTimeSlots,
    getEventDays,
    formatDate,
    relativeDateLabel,
} from '@/lib/eventValidation';

type TabKey = 'ongoing' | 'upcoming' | 'completed' | 'pending' | 'declined';
type Point = { lat: number; lng: number };

type CheckpointSlot = {
    has_afternoon?: boolean;
    afternoon_enabled?: boolean;
    morning_time_in_start?: string;
    morning_time_in_end?: string;
    morning_time_out_start?: string;
    morning_time_out_end?: string;
    afternoon_time_in_start?: string;
    afternoon_time_in_end?: string;
    afternoon_time_out_start?: string;
    afternoon_time_out_end?: string;
    [key: string]: string | boolean | undefined;
};

type ScheduleItem = {
    date: string;
    slots: CheckpointSlot[];
};

type EventItem = {
    event_id: number;
    title: string;
    description: string | null;
    location: string | null;
    is_geofenced: boolean;
    geofence_type: 'radius' | 'polygon';
    latitude: number | null;
    longitude: number | null;
    radius_meters: number;
    geofence_polygon: Point[] | null;
    target_scope: 'all' | 'section';
    target_sections: string[] | null;
    event_date: string;
    event_end_date: string | null;
    schedules: ScheduleItem[] | null;
    approval_status: 'approved' | 'pending' | 'declined';
    is_active: boolean;
    attendance_count?: number;
    target_headcount?: number;
};

type VenueItem = {
    location: string;
    latitude: number | null;
    longitude: number | null;
    radius_meters: number;
};

type PageLink = { url: string | null; label: string; active: boolean };

type Props = {
    events: {
        data: EventItem[];
        links: PageLink[];
    };
    counts?: Record<TabKey, number>;
    venues?: VenueItem[];
    availableSections?: string[];
    filters: { search?: string; tab?: TabKey };
};

const TABS: { key: TabKey; label: string; activeColor: string }[] = [
    {
        key: 'ongoing',
        label: 'On Going',
        activeColor: 'text-[#1B1F5C] border-[#1B1F5C] bg-[#1B1F5C]/5',
    },
    {
        key: 'upcoming',
        label: 'Upcoming',
        activeColor: 'text-emerald-800 border-emerald-600 bg-emerald-50/70',
    },
    {
        key: 'completed',
        label: 'Completed',
        activeColor: 'text-[#1B1F5C] border-[#1B1F5C] bg-[#1B1F5C]/5',
    },
    {
        key: 'pending',
        label: 'Pending Approval',
        activeColor: 'text-amber-800 border-amber-600 bg-amber-50/70',
    },
    {
        key: 'declined',
        label: 'Declined',
        activeColor: 'text-rose-800 border-rose-600 bg-rose-50/70',
    },
];

const DEFAULT_SLOT: CheckpointSlot = {
    has_afternoon: false,
    afternoon_enabled: false,
    morning_time_in_start: '08:00',
    morning_time_in_end: '08:30',
    morning_time_out_start: '11:30',
    morning_time_out_end: '12:00',
    afternoon_time_in_start: '13:00',
    afternoon_time_in_end: '13:30',
    afternoon_time_out_start: '16:30',
    afternoon_time_out_end: '17:00',
};

const WIZARD_STEPS = [
    { step: 1, title: 'Schedule & Audience', subtitle: 'Basic Info, Target Audience & Checkpoint Ranges' },
    { step: 2, title: 'Venue & Geofence', subtitle: 'Venue Location & GPS Boundary' },
    { step: 3, title: 'Review & Publish', subtitle: 'Review & Confirmation' },
];

export default function Events({
    events,
    counts = { ongoing: 0, upcoming: 0, completed: 0, pending: 0, declined: 0 },
    venues = [],
    availableSections = [],
    filters,
}: Props) {
    const [search, setSearch] = useState(filters.search || '');
    const [activeTab, setActiveTab] = useState<TabKey>(filters.tab || 'ongoing');
    const [isFiltering, setIsFiltering] = useState(false);
    const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const isFirstRun = useRef(true);
    const isEditingLoad = useRef(false);

    // Wizard Flow States
    const [currentStep, setCurrentStep] = useState<number>(1);
    const [isMultiDay, setIsMultiDay] = useState(false);
    const [scheduleMode, setScheduleMode] = useState<'uniform' | 'custom'>('uniform');
    const [timeValidationError, setTimeValidationError] = useState<string | null>(null);
    const [stepValidationErrors, setStepValidationErrors] = useState<string[]>([]);
    const [stepThreeReady, setStepThreeReady] = useState(false);

    // Uniform schedule state
    const [uniformSchedule, setUniformSchedule] = useState<CheckpointSlot>(DEFAULT_SLOT);

    // Modal & Alert States
    const [isFormOpen, setIsFormOpen] = useState(false);
    const [editingEvent, setEditingEvent] = useState<EventItem | null>(null);
    const [isDeleteOpen, setIsDeleteOpen] = useState(false);
    const [selectedEvent, setSelectedEvent] = useState<EventItem | null>(null);
    const [isDeleting, setIsDeleting] = useState(false);
    const [successMessage, setSuccessMessage] = useState<string | null>(null);
    const [isSearchingLocation, setIsSearchingLocation] = useState(false);
    const [geocodeConfirmation, setGeocodeConfirmation] = useState<string | null>(null);
    const [geocodeError, setGeocodeError] = useState<string | null>(null);
    const [quickActionEventId, setQuickActionEventId] = useState<number | null>(null);

    const { data, setData, post, put, processing, errors, reset, clearErrors, transform } = useForm({
        title: '',
        description: '',
        location: '',
        is_geofenced: false,
        geofence_type: 'radius' as 'radius' | 'polygon',
        latitude: 18.1972 as number | null,
        longitude: 120.5928 as number | null,
        radius_meters: 100,
        geofence_polygon: null as Point[] | null,
        target_scope: 'all' as 'all' | 'section',
        target_sections: [] as string[],
        event_date: '',
        event_end_date: '' as string | null,
        schedules: [] as ScheduleItem[],
        approval_status: 'approved' as 'approved' | 'pending' | 'declined',
        is_active: true,
    });

    const hasFormErrors = Object.keys(errors).length > 0;
    const hasWizardErrors =
        hasFormErrors || Boolean(timeValidationError) || stepValidationErrors.length > 0;

    // Prevent click bleed-through or Enter key bounce from Step 2 auto-triggering Step 3 save
    useEffect(() => {
        if (currentStep === 3) {
            setStepThreeReady(false);
            const timer = setTimeout(() => setStepThreeReady(true), 250);
            return () => clearTimeout(timer);
        } else {
            setStepThreeReady(false);
        }
    }, [currentStep]);

    // Escape key closes open wizard modal safely
    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.key === 'Escape' && isFormOpen && !processing) {
                setIsFormOpen(false);
            }
        };
        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [isFormOpen, processing]);

    useEffect(() => {
        if (!data.event_date) return;

        if (isEditingLoad.current) {
            isEditingLoad.current = false;
            return;
        }

        const days = getEventDays(data.event_date, isMultiDay ? data.event_end_date : null);

        const newSchedules = days.map((day) => {
            const existing = data.schedules.find((s) => s.date === day);
            if (existing && existing.slots && existing.slots.length > 0) {
                return existing;
            }

            if (scheduleMode === 'uniform' && isMultiDay) {
                return {
                    date: day,
                    slots: [{ ...uniformSchedule }],
                };
            }

            return {
                date: day,
                slots: [{ ...DEFAULT_SLOT }],
            };
        });

        if (newSchedules.length !== data.schedules.length) {
            setData('schedules', newSchedules);
        }
        validateTimeSlots(data.schedules as any, setTimeValidationError);
    }, [data.event_date, data.event_end_date, isMultiDay, scheduleMode]);

    const handleUniformChange = (field: string, value: string | boolean) => {
        const updatedUniform = { ...uniformSchedule, [field]: value };
        if (field === 'has_afternoon') {
            updatedUniform.afternoon_enabled = Boolean(value);
        }
        setUniformSchedule(updatedUniform);
        if (stepValidationErrors.length > 0) setStepValidationErrors([]);

        if (scheduleMode === 'uniform') {
            const updatedSchedules = data.schedules.map((s) => ({
                ...s,
                slots: s.slots.map((slot) => ({
                    ...slot,
                    [field]: value,
                    ...(field === 'has_afternoon' ? { afternoon_enabled: value } : {}),
                })),
            })) as ScheduleItem[];

            setData('schedules', updatedSchedules);
            validateTimeSlots(updatedSchedules as any, setTimeValidationError);
        }
    };

    useEffect(() => {
        if (successMessage) {
            const timer = setTimeout(() => setSuccessMessage(null), 5000);
            return () => clearTimeout(timer);
        }
    }, [successMessage]);

    useEffect(() => {
        if (isFirstRun.current) {
            isFirstRun.current = false;
            return;
        }

        if (debounceRef.current) clearTimeout(debounceRef.current);
        setIsFiltering(true);

        debounceRef.current = setTimeout(() => {
            router.get(
                '/admin/events',
                { search, tab: activeTab },
                {
                    preserveState: true,
                    replace: true,
                    onFinish: () => setIsFiltering(false),
                }
            );
        }, 350);

        return () => {
            if (debounceRef.current) clearTimeout(debounceRef.current);
        };
    }, [search]);

    const validateSlotCompleteness = (slot: CheckpointSlot, labelPrefix: string): string[] => {
        const missing: string[] = [];

        if (!slot.morning_time_in_start || !slot.morning_time_in_end) {
            missing.push(`${labelPrefix}: Morning Time-In start and cut-off times are required.`);
        }
        if (!slot.morning_time_out_start || !slot.morning_time_out_end) {
            missing.push(`${labelPrefix}: Morning Time-Out start and cut-off times are required.`);
        }

        const hasAfternoon = Boolean(slot.has_afternoon || slot.afternoon_enabled);
        if (hasAfternoon) {
            if (!slot.afternoon_time_in_start || !slot.afternoon_time_in_end) {
                missing.push(`${labelPrefix}: Afternoon Time-In start and cut-off times are required.`);
            }
            if (!slot.afternoon_time_out_start || !slot.afternoon_time_out_end) {
                missing.push(`${labelPrefix}: Afternoon Time-Out start and cut-off times are required.`);
            }
        }

        return missing;
    };

    const validateStepOne = (): boolean => {
        const issues: string[] = [];

        if (!data.title || data.title.trim() === '') {
            issues.push('Event Title is required.');
        }

        if (data.target_scope === 'section' && data.target_sections.length === 0) {
            issues.push('Please select at least one target course/section or switch to All Students.');
        }

        if (!data.event_date) {
            issues.push(isMultiDay ? 'Start Date is required.' : 'Event Date is required.');
        }

        if (isMultiDay) {
            if (!data.event_end_date) {
                issues.push('End Date is required for a multi-day event.');
            } else if (data.event_date && data.event_end_date < data.event_date) {
                issues.push('End Date cannot be earlier than the Start Date.');
            }
        }

        if (isMultiDay && scheduleMode === 'uniform') {
            issues.push(...validateSlotCompleteness(uniformSchedule, 'Uniform Schedule'));
        } else {
            if (!data.schedules || data.schedules.length === 0) {
                issues.push('At least one schedule day with checkpoint times is required.');
            } else {
                data.schedules.forEach((schedule, dayIdx) => {
                    const dayPrefix = isMultiDay ? `Day ${dayIdx + 1}` : 'Schedule';
                    if (!schedule.slots || schedule.slots.length === 0) {
                        issues.push(`${dayPrefix}: At least one time slot is required.`);
                    } else {
                        schedule.slots.forEach((slot, slotIdx) => {
                            issues.push(
                                ...validateSlotCompleteness(slot, `${dayPrefix} Slot ${slotIdx + 1}`)
                            );
                        });
                    }
                });
            }
        }

        const timesAreOrdered = validateTimeSlots(data.schedules as any, setTimeValidationError);

        setStepValidationErrors(issues);
        return issues.length === 0 && timesAreOrdered;
    };

    const validateStepTwo = (): boolean => {
        const issues: string[] = [];

        if (!data.location || data.location.trim() === '') {
            issues.push('Venue Name is required.');
        }

        if (data.is_geofenced) {
            if (data.geofence_type === 'radius') {
                if (data.latitude === null || data.longitude === null) {
                    issues.push('Please pin a valid venue coordinate on the map for the geofence.');
                }
            } else if (data.geofence_type === 'polygon') {
                if (!data.geofence_polygon || data.geofence_polygon.length < 3) {
                    issues.push('Please define a valid hexagon boundary area on the map.');
                }
            }
        }

        setStepValidationErrors(issues);
        return issues.length === 0;
    };

    const handleNextStep = () => {
        if (currentStep === 1) {
            if (!validateStepOne()) return;
            setStepValidationErrors([]);
            setCurrentStep(2);
            return;
        }

        if (currentStep === 2) {
            if (!validateStepTwo()) return;
            setStepValidationErrors([]);
            setCurrentStep(3);
        }
    };

    const geocodeVenueName = async (queryLocation?: string) => {
        const targetLocation = queryLocation || data.location;
        if (!targetLocation || targetLocation.trim() === '') return;

        setIsSearchingLocation(true);
        setGeocodeConfirmation(null);
        setGeocodeError(null);
        try {
            const response = await fetch(
                `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(targetLocation)}`
            );
            const results = await response.json();

            if (results && results.length > 0) {
                const topMatch = results[0];
                const newLat = parseFloat(topMatch.lat);
                const newLng = parseFloat(topMatch.lon);

                const radiusMeters = data.radius_meters || 50;
                const latOffset = radiusMeters / 111111;
                const lngOffset = radiusMeters / (111111 * Math.cos((newLat * Math.PI) / 180));

                const newHexagon: Point[] = [];
                for (let i = 0; i < 6; i++) {
                    const angle = (i * 60 * Math.PI) / 180;
                    newHexagon.push({
                        lat: newLat + latOffset * Math.sin(angle),
                        lng: newLng + lngOffset * Math.cos(angle),
                    });
                }

                setData((prev) => ({
                    ...prev,
                    location: targetLocation,
                    latitude: newLat,
                    longitude: newLng,
                    geofence_polygon: newHexagon,
                }));

                setGeocodeConfirmation(
                    topMatch.display_name || `${newLat.toFixed(5)}, ${newLng.toFixed(5)}`
                );
            } else {
                setGeocodeConfirmation(null);
                setGeocodeError('Location not found. Try adding a city, campus, or landmark.');
            }
        } catch (error) {
            console.error('Error fetching venue geocode:', error);
            setGeocodeError(
                'Unable to reach map lookup service. Check your connection or pin manually on the map.'
            );
        } finally {
            setIsSearchingLocation(false);
        }
    };

    const handleApplyVenuePreset = (venue: VenueItem) => {
        setGeocodeError(null);
        setStepValidationErrors([]);
        setData((prev) => ({
            ...prev,
            location: venue.location,
            latitude: venue.latitude !== null ? Number(venue.latitude) : prev.latitude,
            longitude: venue.longitude !== null ? Number(venue.longitude) : prev.longitude,
            radius_meters: venue.radius_meters ? Number(venue.radius_meters) : prev.radius_meters,
        }));
        setGeocodeConfirmation(venue.location);
    };

    const handleTabChange = (tabKey: TabKey) => {
        setActiveTab(tabKey);
        setIsFiltering(true);
        router.get(
            '/admin/events',
            { search, tab: tabKey },
            { preserveState: true, replace: true, onFinish: () => setIsFiltering(false) }
        );
    };

    const handleQuickStatusChange = (eventItem: EventItem, newStatus: 'approved' | 'declined') => {
        setQuickActionEventId(eventItem.event_id);
        router.patch(
            `/admin/events/${eventItem.event_id}/status`,
            { approval_status: newStatus },
            {
                preserveScroll: true,
                onSuccess: () =>
                    setSuccessMessage(`Event "${eventItem.title}" updated to ${newStatus}.`),
                onFinish: () => setQuickActionEventId(null),
            }
        );
    };

    const openCreateModal = () => {
        isEditingLoad.current = false;
        setEditingEvent(null);
        reset();
        clearErrors();
        setCurrentStep(1);
        setIsMultiDay(false);
        setScheduleMode('uniform');
        setUniformSchedule(DEFAULT_SLOT);
        setGeocodeConfirmation(null);
        setGeocodeError(null);
        setTimeValidationError(null);
        setStepValidationErrors([]);
        setStepThreeReady(false);

        setData((prev) => ({
            ...prev,
            approval_status: 'approved',
            is_active: true,
            event_end_date: '',
            schedules: [],
            target_scope: 'all',
            target_sections: [],
        }));

        setIsFormOpen(true);
    };

    const openEditModal = (eventItem: EventItem, isClone = false) => {
        isEditingLoad.current = true;
        const clonedEvent = structuredClone(eventItem);

        if (isClone) {
            setEditingEvent(null);
        } else {
            setEditingEvent(clonedEvent);
        }
        clearErrors();
        setCurrentStep(1);
        setGeocodeConfirmation(null);
        setGeocodeError(null);
        setTimeValidationError(null);
        setStepValidationErrors([]);
        setStepThreeReady(false);

        const hasMultiDay = Boolean(
            clonedEvent.event_end_date && clonedEvent.event_end_date !== clonedEvent.event_date
        );
        setIsMultiDay(hasMultiDay);

        const savedLat =
            clonedEvent.latitude !== null && clonedEvent.latitude !== undefined
                ? Number(clonedEvent.latitude)
                : 18.1972;
        const savedLng =
            clonedEvent.longitude !== null && clonedEvent.longitude !== undefined
                ? Number(clonedEvent.longitude)
                : 120.5928;

        const hasExistingSchedules = clonedEvent.schedules && clonedEvent.schedules.length > 0;

        const mappedSchedules = hasExistingSchedules
            ? clonedEvent.schedules!.map((sch) => ({
                  date: sch.date,
                  slots:
                      sch.slots && sch.slots.length > 0
                          ? sch.slots.map((s) => {
                                const hasStoredAfternoon =
                                    Boolean(s.has_afternoon) ||
                                    Boolean(s.afternoon_enabled) ||
                                    Boolean(s.afternoon_time_in_start) ||
                                    Boolean(s.afternoon_time_out_start);
                                return {
                                    ...DEFAULT_SLOT,
                                    ...s,
                                    has_afternoon: hasStoredAfternoon,
                                    afternoon_enabled: hasStoredAfternoon,
                                };
                            })
                          : [{ ...DEFAULT_SLOT }],
              }))
            : getEventDays(clonedEvent.event_date, clonedEvent.event_end_date).map((day) => ({
                  date: day,
                  slots: [{ ...DEFAULT_SLOT }],
              }));

        const containsMultipleSlots = mappedSchedules.some((s) => s.slots && s.slots.length > 1);
        if (containsMultipleSlots || (hasMultiDay && mappedSchedules.length > 1)) {
            setScheduleMode('custom');
        } else {
            setScheduleMode('uniform');
            if (mappedSchedules[0]?.slots[0]) {
                setUniformSchedule({
                    ...DEFAULT_SLOT,
                    ...mappedSchedules[0].slots[0],
                });
            }
        }

        setData({
            title: isClone ? `${clonedEvent.title} (Copy)` : clonedEvent.title,
            description: clonedEvent.description || '',
            location: clonedEvent.location || '',
            is_geofenced: Boolean(clonedEvent.is_geofenced),
            geofence_type: clonedEvent.geofence_type || 'radius',
            latitude: savedLat,
            longitude: savedLng,
            radius_meters: Number(clonedEvent.radius_meters) || 100,
            geofence_polygon:
                clonedEvent.geofence_polygon && clonedEvent.geofence_polygon.length >= 3
                    ? clonedEvent.geofence_polygon
                    : null,
            target_scope: clonedEvent.target_scope || 'all',
            target_sections: clonedEvent.target_sections || [],
            event_date: isClone ? '' : clonedEvent.event_date,
            event_end_date: isClone ? '' : clonedEvent.event_end_date || '',
            schedules: isClone ? [] : mappedSchedules,
            approval_status: clonedEvent.approval_status || 'approved',
            is_active: Boolean(clonedEvent.is_active),
        });

        setIsFormOpen(true);
    };

    const handleExplicitSave = () => {
        if (currentStep !== 3 || !stepThreeReady || processing) return;

        if (!validateStepOne() || !validateStepTwo()) {
            return;
        }

        transform((currentData) => ({
            ...currentData,
            event_end_date: isMultiDay ? currentData.event_end_date : null,
        }));

        if (editingEvent) {
            put(`/admin/events/${editingEvent.event_id}`, {
                preserveScroll: true,
                onSuccess: () => {
                    setIsFormOpen(false);
                    setSuccessMessage(`Event "${data.title}" updated successfully.`);
                },
            });
        } else {
            post('/admin/events', {
                preserveScroll: true,
                onSuccess: () => {
                    setIsFormOpen(false);
                    reset();
                    setSuccessMessage('New event created successfully.');
                },
            });
        }
    };

    const promptDelete = (eventItem: EventItem) => {
        setSelectedEvent(eventItem);
        setIsDeleteOpen(true);
    };

    const confirmDelete = () => {
        if (!selectedEvent) return;
        setIsDeleting(true);
        router.delete(`/admin/events/${selectedEvent.event_id}`, {
            onSuccess: () => {
                setIsDeleteOpen(false);
                setSuccessMessage(`Event "${selectedEvent.title}" deleted.`);
                setSelectedEvent(null);
            },
            onFinish: () => setIsDeleting(false),
        });
    };

    const activeStepInfo = WIZARD_STEPS[currentStep - 1] ?? WIZARD_STEPS[0];

    return (
        <>
            <Head title="Events Management | 4ttend Attendance System" />

            <div className="min-h-screen space-y-4 bg-[#F5F6FA] p-3 font-sans text-gray-900 antialiased sm:p-5">
                {successMessage && (
                    <div
                        role="status"
                        aria-live="polite"
                        className="flex items-center justify-between gap-3 rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-emerald-900 shadow-xs"
                    >
                        <div className="flex items-center gap-2.5 text-xs font-bold sm:text-sm">
                            <CheckCircle2
                                className="h-5 w-5 shrink-0 text-emerald-600"
                                aria-hidden="true"
                            />
                            <span>{successMessage}</span>
                        </div>
                        <button
                            type="button"
                            onClick={() => setSuccessMessage(null)}
                            className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-lg text-emerald-700 transition-colors hover:bg-emerald-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            aria-label="Dismiss success notification"
                        >
                            <X className="h-4 w-4" aria-hidden="true" />
                        </button>
                    </div>
                )}

                {/* PAGE HEADER */}
                <header className="flex flex-col items-start justify-between gap-3 rounded-2xl border border-gray-200/80 bg-white p-4 shadow-xs sm:flex-row sm:items-center sm:p-5">
                    <div className="space-y-0.5">
                        <h1 className="text-xl font-black tracking-tight text-[#1B1F5C] sm:text-2xl">
                            Events Management
                        </h1>
                        <p className="text-xs font-medium text-gray-600">
                            Configure session checkpoints with start-to-cutoff time ranges and optional afternoon blocks.
                        </p>
                    </div>

                    <button
                        type="button"
                        onClick={openCreateModal}
                        className="inline-flex min-h-[44px] shrink-0 items-center justify-center gap-2 rounded-xl bg-[#1B1F5C] px-4 py-2.5 text-xs font-bold text-white shadow-xs transition-colors hover:bg-[#131644] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] active:scale-[0.99] motion-reduce:transform-none"
                    >
                        <Plus className="h-4 w-4 text-[#F5A623]" aria-hidden="true" />
                        <span>Create New Event</span>
                    </button>
                </header>

                {/* TABS & SEARCH TOOLBAR */}
                <div className="space-y-3 rounded-2xl border border-gray-200/80 bg-white p-3.5 shadow-xs sm:p-4">
                    <nav aria-label="Events status filter tabs">
                        <div
                            role="tablist"
                            className="flex space-x-2 overflow-x-auto border-b border-gray-100 pb-2 sm:space-x-4"
                        >
                            {TABS.map((tab) => {
                                const isActive = activeTab === tab.key;
                                const count = counts?.[tab.key] ?? 0;
                                return (
                                    <button
                                        key={tab.key}
                                        type="button"
                                        role="tab"
                                        aria-selected={isActive}
                                        onClick={() => handleTabChange(tab.key)}
                                        className={`flex min-h-[38px] items-center gap-2 whitespace-nowrap rounded-xl border px-3 py-1.5 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                            isActive
                                                ? tab.activeColor
                                                : 'border-transparent text-gray-600 hover:bg-gray-50 hover:text-[#1B1F5C]'
                                        }`}
                                    >
                                        <span>{tab.label}</span>
                                        <span
                                            className={`rounded-full px-2 py-0.5 text-[11px] font-extrabold transition-opacity ${
                                                isActive
                                                    ? 'bg-white text-[#1B1F5C] shadow-2xs'
                                                    : 'bg-gray-100 text-gray-600'
                                            } ${isFiltering && isActive ? 'opacity-50' : 'opacity-100'}`}
                                        >
                                            {count}
                                        </span>
                                    </button>
                                );
                            })}
                        </div>
                    </nav>

                    <div className="flex flex-wrap items-center justify-between gap-2">
                        <div className="relative w-full sm:w-80">
                            {isFiltering ? (
                                <Loader2
                                    className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-gray-400 motion-reduce:animate-none"
                                    aria-hidden="true"
                                />
                            ) : (
                                <Search
                                    className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400"
                                    aria-hidden="true"
                                />
                            )}
                            <input
                                type="text"
                                placeholder="Search event title, location..."
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white py-1.5 pl-10 pr-8 text-xs font-medium text-gray-900 placeholder:text-gray-400 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                aria-label="Search events by title or location"
                            />
                            {search && (
                                <button
                                    type="button"
                                    onClick={() => setSearch('')}
                                    className="absolute right-2 top-1/2 -translate-y-1/2 rounded-md p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    aria-label="Clear search"
                                >
                                    <X className="h-3.5 w-3.5" aria-hidden="true" />
                                </button>
                            )}
                        </div>
                    </div>
                </div>

                {/* EVENTS RECORDS (MOBILE CARDS + DESKTOP TABLE) */}
                <main
                    aria-label="Events Directory"
                    className="overflow-hidden rounded-2xl border border-gray-200/80 bg-white shadow-xs"
                >
                    {/* MOBILE & TABLET CARD VIEW (< lg) */}
                    <div className="divide-y divide-gray-100 lg:hidden" aria-live="polite">
                        {events.data.length > 0 ? (
                            events.data.map((item) => {
                                const relLabel = relativeDateLabel(item.event_date);
                                const isQuickActing = quickActionEventId === item.event_id;
                                const slot = item?.schedules?.[0]?.slots?.[0];
                                const hasAfternoon = Boolean(slot?.has_afternoon || slot?.afternoon_enabled);
                                const morningIn =
                                    typeof slot?.morning_time_in_start === 'string'
                                        ? slot.morning_time_in_start
                                        : typeof slot?.time_in_start === 'string'
                                          ? slot.time_in_start
                                          : undefined;
                                const morningOut =
                                    typeof slot?.morning_time_out_start === 'string'
                                        ? slot.morning_time_out_start
                                        : typeof slot?.time_out_start === 'string'
                                          ? slot.time_out_start
                                          : undefined;

                                return (
                                    <article key={item.event_id} className="space-y-3 p-4">
                                        <div className="flex items-start justify-between gap-2">
                                            <div className="min-w-0">
                                                <Link
                                                    href={`/admin/analytics/events/${item.event_id}`}
                                                    className="block truncate text-sm font-black text-[#1B1F5C] hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                >
                                                    {item.title}
                                                </Link>
                                                <div className="mt-1 flex flex-wrap items-center gap-1.5 text-xs font-medium text-gray-600">
                                                    <span>
                                                        {formatDate(item.event_date)}
                                                        {item.event_end_date &&
                                                        item.event_end_date !== item.event_date
                                                            ? ` - ${formatDate(item.event_end_date)}`
                                                            : ''}
                                                    </span>
                                                    {relLabel && (
                                                        <span className="rounded-full bg-gray-100 px-2 py-0.5 text-[10px] font-bold text-gray-700">
                                                            {relLabel}
                                                        </span>
                                                    )}
                                                </div>
                                            </div>

                                            <span
                                                className={`inline-flex shrink-0 items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-bold ${
                                                    item.is_active
                                                        ? 'border-emerald-200 bg-emerald-50 text-emerald-800'
                                                        : 'border-gray-200 bg-gray-100 text-gray-600'
                                                }`}
                                            >
                                                <span
                                                    className={`h-2 w-2 rounded-full ${
                                                        item.is_active
                                                            ? 'bg-emerald-500'
                                                            : 'bg-gray-400'
                                                    }`}
                                                    aria-hidden="true"
                                                />
                                                {item.is_active ? 'Active' : 'Inactive'}
                                            </span>
                                        </div>

                                        <div className="grid grid-cols-1 gap-2 rounded-xl border border-gray-200/80 bg-[#F5F6FA]/70 p-3 text-xs sm:grid-cols-2">
                                            <div className="space-y-1">
                                                <p className="flex items-center gap-1.5 font-bold text-gray-900">
                                                    <MapPin
                                                        className="h-3.5 w-3.5 shrink-0 text-[#F5A623]"
                                                        aria-hidden="true"
                                                    />
                                                    <span className="truncate">
                                                        {item.location || 'Unspecified Venue'}
                                                    </span>
                                                </p>
                                                <p className="text-[11px] font-semibold text-gray-600">
                                                    {item.is_geofenced
                                                        ? item.geofence_type === 'polygon'
                                                            ? 'Hexagon Boundary'
                                                            : `Radius (${item.radius_meters}m)`
                                                        : 'Location Free'}{' '}
                                                    •{' '}
                                                    {item.target_scope === 'all'
                                                        ? 'All Students'
                                                        : `${item.target_sections?.length || 0} Section(s)`}
                                                </p>
                                            </div>

                                            <div className="space-y-1">
                                                <p className="font-semibold text-blue-800">
                                                    AM: {formatAMPM(morningIn)} –{' '}
                                                    {formatAMPM(morningOut)}
                                                </p>
                                                <p className="font-semibold text-amber-800">
                                                    PM:{' '}
                                                    {hasAfternoon
                                                        ? `${formatAMPM(slot?.afternoon_time_in_start)} – ${formatAMPM(slot?.afternoon_time_out_start)}`
                                                        : 'Disabled'}
                                                </p>
                                            </div>
                                        </div>

                                        <div className="flex flex-wrap items-center justify-end gap-1.5 border-t border-gray-100 pt-2">
                                            {activeTab === 'pending' && (
                                                <>
                                                    <button
                                                        type="button"
                                                        onClick={() =>
                                                            handleQuickStatusChange(
                                                                item,
                                                                'approved'
                                                            )
                                                        }
                                                        disabled={isQuickActing}
                                                        aria-label={`Approve ${item.title}`}
                                                        className="inline-flex min-h-[38px] items-center gap-1 rounded-lg border border-emerald-200 bg-emerald-50 px-2.5 py-1.5 text-xs font-bold text-emerald-800 hover:bg-emerald-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-40"
                                                    >
                                                        <Check className="h-3.5 w-3.5" aria-hidden="true" />
                                                        <span>Approve</span>
                                                    </button>
                                                    <button
                                                        type="button"
                                                        onClick={() =>
                                                            handleQuickStatusChange(
                                                                item,
                                                                'declined'
                                                            )
                                                        }
                                                        disabled={isQuickActing}
                                                        aria-label={`Decline ${item.title}`}
                                                        className="inline-flex min-h-[38px] items-center gap-1 rounded-lg border border-rose-200 bg-rose-50 px-2.5 py-1.5 text-xs font-bold text-rose-800 hover:bg-rose-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-40"
                                                    >
                                                        <XCircle className="h-3.5 w-3.5" aria-hidden="true" />
                                                        <span>Decline</span>
                                                    </button>
                                                </>
                                            )}
                                            <button
                                                type="button"
                                                onClick={() => openEditModal(item, true)}
                                                aria-label={`Duplicate ${item.title}`}
                                                className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-lg border border-gray-200 bg-white p-2 text-gray-600 hover:bg-gray-50 hover:text-[#1B1F5C] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                            >
                                                <Copy className="h-4 w-4" aria-hidden="true" />
                                            </button>
                                            <button
                                                type="button"
                                                onClick={() => openEditModal(item)}
                                                aria-label={`Edit ${item.title}`}
                                                className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-lg border border-gray-200 bg-white p-2 text-gray-600 hover:bg-gray-50 hover:text-[#1B1F5C] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                            >
                                                <Pencil className="h-4 w-4" aria-hidden="true" />
                                            </button>
                                            <button
                                                type="button"
                                                onClick={() => promptDelete(item)}
                                                aria-label={`Delete ${item.title}`}
                                                className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-lg border border-rose-200 bg-rose-50/70 p-2 text-rose-700 hover:bg-rose-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                            >
                                                <Trash2 className="h-4 w-4" aria-hidden="true" />
                                            </button>
                                        </div>
                                    </article>
                                );
                            })
                        ) : (
                            <EmptyEventsState
                                activeTab={activeTab}
                                hasSearch={search.trim() !== ''}
                                onClearSearch={() => setSearch('')}
                                onCreate={openCreateModal}
                            />
                        )}
                    </div>

                    {/* DESKTOP DATA TABLE (>= lg) */}
                    <div className="hidden overflow-x-auto lg:block">
                        <table className="w-full text-left text-xs text-gray-700 sm:text-sm">
                            <thead className="border-b border-gray-200/80 bg-gray-50/80 text-[10px] font-extrabold uppercase tracking-wider text-gray-500">
                                <tr>
                                    <th scope="col" className="px-5 py-3">
                                        Event Details
                                    </th>
                                    <th scope="col" className="px-4 py-3">
                                        Target Audience
                                    </th>
                                    <th scope="col" className="px-4 py-3">
                                        Venue & Geofence
                                    </th>
                                    <th scope="col" className="px-4 py-3">
                                        Morning Checkpoints
                                    </th>
                                    <th scope="col" className="px-4 py-3">
                                        Afternoon Checkpoints
                                    </th>
                                    <th scope="col" className="px-4 py-3">
                                        Status
                                    </th>
                                    <th scope="col" className="px-5 py-3 text-right">
                                        Actions
                                    </th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100 text-xs sm:text-sm" aria-live="polite">
                                {events.data.length > 0 ? (
                                    events.data.map((item) => {
                                        const relLabel = relativeDateLabel(item.event_date);
                                        const isQuickActing = quickActionEventId === item.event_id;
                                        const slot = item?.schedules?.[0]?.slots?.[0];
                                        const hasAfternoon = Boolean(slot?.has_afternoon || slot?.afternoon_enabled);
                                        return (
                                            <tr
                                                key={item.event_id}
                                                className="transition-colors hover:bg-[#F5F6FA]/70"
                                            >
                                                {/* 1. Event Details */}
                                                <td className="max-w-[240px] px-5 py-3.5">
                                                    <Link
                                                        href={`/admin/analytics/events/${item.event_id}`}
                                                        className="group block rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                    >
                                                        <div
                                                            className="truncate text-sm font-extrabold text-[#1B1F5C] group-hover:underline"
                                                            title={item.title}
                                                        >
                                                            {item.title}
                                                        </div>
                                                        <div className="mt-1 flex items-center gap-2 text-xs font-medium text-gray-500">
                                                            <span>
                                                                {formatDate(item.event_date)}
                                                                {item.event_end_date &&
                                                                item.event_end_date !==
                                                                    item.event_date
                                                                    ? ` - ${formatDate(item.event_end_date)}`
                                                                    : ''}
                                                            </span>
                                                            {relLabel && (
                                                                <span className="rounded-full bg-gray-100 px-2 py-0.5 text-[10px] font-bold text-gray-600">
                                                                    {relLabel}
                                                                </span>
                                                            )}
                                                        </div>
                                                    </Link>
                                                </td>

                                                {/* 2. Target Audience */}
                                                <td className="px-4 py-3.5">
                                                    <span className="inline-flex items-center gap-1.5 rounded-xl border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 px-2.5 py-1 text-xs font-bold text-[#1B1F5C]">
                                                        <span>
                                                            {item.target_scope === 'all'
                                                                ? 'All Students'
                                                                : `${item.target_sections?.length || 0} Section(s)`}
                                                        </span>
                                                    </span>
                                                </td>

                                                {/* 3. Venue & Geofence */}
                                                <td className="px-4 py-3.5">
                                                    <Link
                                                        href={`/admin/analytics/events/${item.event_id}`}
                                                        className="block rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                    >
                                                        <div className="flex items-center gap-1.5 font-bold text-gray-900">
                                                            <MapPin
                                                                className="h-4 w-4 shrink-0 text-[#F5A623]"
                                                                aria-hidden="true"
                                                            />
                                                            <span
                                                                className="max-w-[150px] truncate"
                                                                title={
                                                                    item.location ||
                                                                    'Unspecified Venue'
                                                                }
                                                            >
                                                                {item.location ||
                                                                    'Unspecified Venue'}
                                                            </span>
                                                        </div>
                                                        {item.is_geofenced ? (
                                                            <span className="mt-1 inline-flex items-center gap-1.5 text-[11px] font-bold text-[#1B1F5C]">
                                                                {item.geofence_type === 'polygon' ? (
                                                                    <Hexagon
                                                                        className="h-3.5 w-3.5 text-[#F5A623]"
                                                                        aria-hidden="true"
                                                                    />
                                                                ) : (
                                                                    <CircleDot
                                                                        className="h-3.5 w-3.5 text-[#F5A623]"
                                                                        aria-hidden="true"
                                                                    />
                                                                )}
                                                                <span>
                                                                    {item.geofence_type === 'polygon'
                                                                        ? 'Hexagon Boundary'
                                                                        : `Radius (${item.radius_meters}m)`}
                                                                </span>
                                                            </span>
                                                        ) : (
                                                            <span className="mt-1 block text-[11px] font-medium text-gray-500">
                                                                Location Free
                                                            </span>
                                                        )}
                                                    </Link>
                                                </td>

                                                {/* 4. Morning Checkpoints */}
                                                <td className="px-4 py-3.5 text-gray-700">
                                                    <Link
                                                        href={`/admin/analytics/events/${item.event_id}`}
                                                        className="block space-y-1 rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                    >
                                                        <div
                                                            className="flex items-center gap-1.5 text-xs font-bold text-blue-800"
                                                            title="Morning Time-In"
                                                        >
                                                            <LogIn
                                                                className="h-3 w-3 shrink-0 text-blue-600"
                                                                aria-hidden="true"
                                                            />
                                                            <span>
                                                                In:{' '}
                                                                {formatAMPM(
                                                                    typeof slot?.morning_time_in_start ===
                                                                        'string'
                                                                        ? slot.morning_time_in_start
                                                                        : typeof slot?.time_in_start ===
                                                                            'string'
                                                                          ? slot.time_in_start
                                                                          : undefined
                                                                )}
                                                            </span>
                                                        </div>
                                                        <div
                                                            className="flex items-center gap-1.5 text-xs font-semibold text-indigo-800"
                                                            title="Morning Time-Out"
                                                        >
                                                            <LogOut
                                                                className="h-3 w-3 shrink-0 text-indigo-600"
                                                                aria-hidden="true"
                                                            />
                                                            <span>
                                                                Out:{' '}
                                                                {formatAMPM(
                                                                    typeof slot?.morning_time_out_start ===
                                                                        'string'
                                                                        ? slot.morning_time_out_start
                                                                        : typeof slot?.time_out_start ===
                                                                            'string'
                                                                          ? slot.time_out_start
                                                                          : undefined
                                                                )}
                                                            </span>
                                                        </div>
                                                    </Link>
                                                </td>

                                                {/* 5. Afternoon Checkpoints */}
                                                <td className="px-4 py-3.5 text-gray-700">
                                                    {hasAfternoon ? (
                                                        <Link
                                                            href={`/admin/analytics/events/${item.event_id}`}
                                                            className="block space-y-1 rounded-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                        >
                                                            <div
                                                                className="flex items-center gap-1.5 text-xs font-bold text-amber-800"
                                                                title="Afternoon Time-In"
                                                            >
                                                                <LogIn
                                                                    className="h-3 w-3 shrink-0 text-amber-600"
                                                                    aria-hidden="true"
                                                                />
                                                                <span>
                                                                    In:{' '}
                                                                    {formatAMPM(
                                                                        slot?.afternoon_time_in_start
                                                                    )}
                                                                </span>
                                                            </div>
                                                            <div
                                                                className="flex items-center gap-1.5 text-xs font-semibold text-purple-800"
                                                                title="Afternoon Time-Out"
                                                            >
                                                                <LogOut
                                                                    className="h-3 w-3 shrink-0 text-purple-600"
                                                                    aria-hidden="true"
                                                                />
                                                                <span>
                                                                    Out:{' '}
                                                                    {formatAMPM(
                                                                        slot?.afternoon_time_out_start
                                                                    )}
                                                                </span>
                                                            </div>
                                                        </Link>
                                                    ) : (
                                                        <span className="text-[11px] font-medium italic text-gray-500">
                                                            Disabled
                                                        </span>
                                                    )}
                                                </td>

                                                {/* 6. Status */}
                                                <td className="px-4 py-3.5">
                                                    <Link
                                                        href={`/admin/analytics/events/${item.event_id}`}
                                                        className="inline-block rounded-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                    >
                                                        <span
                                                            className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-bold ${
                                                                item.is_active
                                                                    ? 'border-emerald-200 bg-emerald-50 text-emerald-800'
                                                                    : 'border-gray-200 bg-gray-100 text-gray-600'
                                                            }`}
                                                        >
                                                            <span
                                                                className={`h-2 w-2 rounded-full ${
                                                                    item.is_active
                                                                        ? 'bg-emerald-500'
                                                                        : 'bg-gray-400'
                                                                }`}
                                                                aria-hidden="true"
                                                            />
                                                            {item.is_active ? 'Active' : 'Inactive'}
                                                        </span>
                                                    </Link>
                                                </td>

                                                {/* 7. Actions */}
                                                <td className="px-5 py-3.5 text-right">
                                                    <div className="inline-flex items-center justify-end gap-1">
                                                        {activeTab === 'pending' && (
                                                            <>
                                                                <button
                                                                    type="button"
                                                                    onClick={() =>
                                                                        handleQuickStatusChange(
                                                                            item,
                                                                            'approved'
                                                                        )
                                                                    }
                                                                    disabled={isQuickActing}
                                                                    className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-lg p-2 text-emerald-700 transition-colors hover:bg-emerald-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-40"
                                                                    title="Approve Event"
                                                                    aria-label={`Approve ${item.title}`}
                                                                >
                                                                    {isQuickActing ? (
                                                                        <Loader2
                                                                            className="h-4 w-4 animate-spin motion-reduce:animate-none"
                                                                            aria-hidden="true"
                                                                        />
                                                                    ) : (
                                                                        <Check
                                                                            className="h-4 w-4"
                                                                            aria-hidden="true"
                                                                        />
                                                                    )}
                                                                </button>
                                                                <button
                                                                    type="button"
                                                                    onClick={() =>
                                                                        handleQuickStatusChange(
                                                                            item,
                                                                            'declined'
                                                                        )
                                                                    }
                                                                    disabled={isQuickActing}
                                                                    className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-lg p-2 text-rose-700 transition-colors hover:bg-rose-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-40"
                                                                    title="Decline Event"
                                                                    aria-label={`Decline ${item.title}`}
                                                                >
                                                                    <XCircle
                                                                        className="h-4 w-4"
                                                                        aria-hidden="true"
                                                                    />
                                                                </button>
                                                            </>
                                                        )}
                                                        <button
                                                            type="button"
                                                            onClick={() =>
                                                                openEditModal(item, true)
                                                            }
                                                            className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-lg p-2 text-gray-500 transition-colors hover:bg-[#1B1F5C]/10 hover:text-[#1B1F5C] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                            title="Duplicate Event"
                                                            aria-label={`Duplicate ${item.title}`}
                                                        >
                                                            <Copy
                                                                className="h-4 w-4"
                                                                aria-hidden="true"
                                                            />
                                                        </button>
                                                        <button
                                                            type="button"
                                                            onClick={() => openEditModal(item)}
                                                            className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-lg p-2 text-gray-500 transition-colors hover:bg-gray-100 hover:text-[#1B1F5C] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                            title="Edit Event"
                                                            aria-label={`Edit ${item.title}`}
                                                        >
                                                            <Pencil
                                                                className="h-4 w-4"
                                                                aria-hidden="true"
                                                            />
                                                        </button>
                                                        <button
                                                            type="button"
                                                            onClick={() => promptDelete(item)}
                                                            className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-lg p-2 text-gray-500 transition-colors hover:bg-rose-50 hover:text-rose-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                            title="Delete Event"
                                                            aria-label={`Delete ${item.title}`}
                                                        >
                                                            <Trash2
                                                                className="h-4 w-4"
                                                                aria-hidden="true"
                                                            />
                                                        </button>
                                                    </div>
                                                </td>
                                            </tr>
                                        );
                                    })
                                ) : (
                                    <tr>
                                        <td colSpan={7}>
                                            <EmptyEventsState
                                                activeTab={activeTab}
                                                hasSearch={search.trim() !== ''}
                                                onClearSearch={() => setSearch('')}
                                                onCreate={openCreateModal}
                                            />
                                        </td>
                                    </tr>
                                )}
                            </tbody>
                        </table>
                    </div>
                </main>

                {events.links.length > 3 && (
                    <nav
                        className="flex flex-wrap items-center justify-center gap-1.5 pt-2"
                        aria-label="Events pagination"
                    >
                        {events.links.map((link, idx) => (
                            <Link
                                key={idx}
                                href={link.url ?? '#'}
                                preserveState
                                preserveScroll
                                aria-current={link.active ? 'page' : undefined}
                                className={`flex min-h-[38px] min-w-[38px] items-center justify-center rounded-xl px-3.5 py-1.5 text-center text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                    link.active
                                        ? 'bg-[#1B1F5C] text-white'
                                        : link.url
                                          ? 'border border-gray-200 bg-white text-gray-700 hover:bg-gray-100'
                                          : 'pointer-events-none border border-gray-100 bg-white text-gray-300'
                                }`}
                                dangerouslySetInnerHTML={{ __html: link.label }}
                            />
                        ))}
                    </nav>
                )}
            </div>

            {/* WIZARD FORM MODAL */}
            {isFormOpen && (
                <div
                    role="dialog"
                    aria-modal="true"
                    aria-labelledby="event-wizard-title"
                    onClick={(e) => {
                        if (e.target === e.currentTarget && !processing) {
                            setIsFormOpen(false);
                        }
                    }}
                    className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-3 sm:p-4"
                >
                    <div className="flex max-h-[92vh] w-full max-w-3xl flex-col overflow-hidden rounded-2xl border border-gray-200/80 bg-white shadow-lg">
                        <header className="space-y-3 border-b border-gray-100 p-4 sm:p-5">
                            <div className="flex items-center justify-between gap-2">
                                <div className="flex items-center gap-3">
                                    <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 text-[#1B1F5C]">
                                        <Calendar className="h-5 w-5" aria-hidden="true" />
                                    </div>
                                    <div>
                                        <h2
                                            id="event-wizard-title"
                                            className="text-base font-black text-[#1B1F5C] sm:text-lg"
                                        >
                                            {editingEvent ? 'Edit Event Details' : 'Create New Event'}
                                        </h2>
                                        <p className="text-xs font-medium text-gray-600">
                                            Step {currentStep} of 3: {activeStepInfo.subtitle}
                                        </p>
                                    </div>
                                </div>
                                <button
                                    type="button"
                                    disabled={processing}
                                    onClick={() => setIsFormOpen(false)}
                                    className="inline-flex min-h-[38px] min-w-[38px] items-center justify-center rounded-lg text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                    aria-label="Close event dialog"
                                >
                                    <X className="h-5 w-5" aria-hidden="true" />
                                </button>
                            </div>

                            {/* NON-CLICKABLE STEP PROGRESS INDICATOR */}
                            <ol className="grid grid-cols-3 gap-2" aria-label="Wizard progress">
                                {WIZARD_STEPS.map((s) => {
                                    const isCurrent = currentStep === s.step;
                                    const isCompleted = currentStep > s.step;
                                    return (
                                        <li
                                            key={s.step}
                                            aria-current={isCurrent ? 'step' : undefined}
                                        >
                                            <div
                                                className={`pointer-events-none flex min-h-[36px] w-full select-none items-center gap-2 rounded-xl border px-2.5 py-1.5 text-left text-xs font-bold ${
                                                    isCurrent
                                                        ? 'border-[#1B1F5C] bg-[#1B1F5C] text-white'
                                                        : isCompleted
                                                          ? 'border-emerald-200 bg-emerald-50 text-emerald-800'
                                                          : 'border-gray-200 bg-gray-50 text-gray-500'
                                                }`}
                                            >
                                                <span
                                                    className={`flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[10px] font-black ${
                                                        isCurrent
                                                            ? 'bg-[#F5A623] text-[#1B1F5C]'
                                                            : isCompleted
                                                              ? 'bg-emerald-600 text-white'
                                                              : 'bg-gray-200 text-gray-700'
                                                    }`}
                                                >
                                                    {isCompleted ? (
                                                        <Check className="h-3 w-3" aria-hidden="true" />
                                                    ) : (
                                                        s.step
                                                    )}
                                                </span>
                                                <span className="truncate">{s.title}</span>
                                            </div>
                                        </li>
                                    );
                                })}
                            </ol>
                        </header>

                        {hasWizardErrors && (
                            <div
                                className="mx-4 mt-4 flex items-start gap-2.5 rounded-xl border border-rose-200 bg-rose-50 p-3.5 text-xs text-rose-800 sm:mx-6 sm:text-sm"
                                role="alert"
                            >
                                <AlertCircle
                                    className="mt-0.5 h-5 w-5 shrink-0 text-rose-600"
                                    aria-hidden="true"
                                />
                                <div>
                                    <p className="font-bold">Please fix the following before continuing:</p>
                                    <ul className="mt-1 list-inside list-disc space-y-0.5 text-xs">
                                        {stepValidationErrors.map((msg, idx) => (
                                            <li key={`step-err-${idx}`}>{msg}</li>
                                        ))}
                                        {timeValidationError && <li>{timeValidationError}</li>}
                                        {Object.values(errors).map((msg, i) => (
                                            <li key={`server-err-${i}`}>{msg}</li>
                                        ))}
                                    </ul>
                                </div>
                            </div>
                        )}

                        <form
                            id="event-form"
                            onSubmit={(e) => e.preventDefault()}
                            className="flex-1 space-y-4 overflow-y-auto p-4 text-xs sm:p-6 sm:text-sm"
                        >
                            {/* STEP 1: BASIC INFO, TARGET AUDIENCE & CHECKPOINT RANGES */}
                            {currentStep === 1 && (
                                <div className="space-y-4">
                                    <div>
                                        <label
                                            htmlFor="event-title"
                                            className="block text-[10px] font-bold uppercase tracking-wider text-gray-600"
                                        >
                                            Event Title <span className="text-rose-600">*</span>
                                        </label>
                                        <input
                                            id="event-title"
                                            type="text"
                                            required
                                            value={data.title}
                                            onChange={(e) => {
                                                setData('title', e.target.value);
                                                if (stepValidationErrors.length > 0) {
                                                    setStepValidationErrors([]);
                                                }
                                            }}
                                            placeholder="e.g. University Sportsfest"
                                            aria-invalid={Boolean(errors.title)}
                                            className="mt-1 min-h-[44px] w-full rounded-xl border border-gray-300 bg-white px-3.5 py-2 text-xs font-medium text-gray-900 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] sm:text-sm"
                                        />
                                    </div>

                                    <div>
                                        <label
                                            htmlFor="event-description"
                                            className="block text-[10px] font-bold uppercase tracking-wider text-gray-600"
                                        >
                                            Description
                                        </label>
                                        <textarea
                                            id="event-description"
                                            rows={2}
                                            value={data.description}
                                            onChange={(e) => setData('description', e.target.value)}
                                            placeholder="Optional details..."
                                            className="mt-1 w-full rounded-xl border border-gray-300 bg-white p-3 text-xs font-medium text-gray-900 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] sm:text-sm"
                                        />
                                    </div>

                                    {/* TARGET AUDIENCE SCOPING */}
                                    <div className="space-y-2">
                                        <span className="block text-[10px] font-bold uppercase tracking-wider text-gray-600">
                                            Participant Target Audience Scope
                                        </span>

                                        <div className="space-y-3 rounded-2xl border border-gray-200/80 bg-[#F5F6FA]/70 p-3.5">
                                            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                                                <button
                                                    type="button"
                                                    aria-pressed={data.target_scope === 'all'}
                                                    onClick={() => {
                                                        setData('target_scope', 'all');
                                                        setData('target_sections', []);
                                                        if (stepValidationErrors.length > 0) {
                                                            setStepValidationErrors([]);
                                                        }
                                                    }}
                                                    className={`flex min-h-[44px] items-center justify-center gap-1.5 rounded-xl px-3 py-2 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                        data.target_scope === 'all'
                                                            ? 'bg-[#1B1F5C] text-white'
                                                            : 'border border-gray-200 bg-white text-gray-700 hover:bg-gray-50'
                                                    }`}
                                                >
                                                    All Students (University-wide)
                                                </button>
                                                <button
                                                    type="button"
                                                    aria-pressed={data.target_scope === 'section'}
                                                    onClick={() => {
                                                        setData('target_scope', 'section');
                                                        if (stepValidationErrors.length > 0) {
                                                            setStepValidationErrors([]);
                                                        }
                                                    }}
                                                    className={`flex min-h-[44px] items-center justify-center gap-1.5 rounded-xl px-3 py-2 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                        data.target_scope === 'section'
                                                            ? 'bg-[#1B1F5C] text-white'
                                                            : 'border border-gray-200 bg-white text-gray-700 hover:bg-gray-50'
                                                    }`}
                                                >
                                                    Specific Course & Sections
                                                </button>
                                            </div>

                                            {data.target_scope === 'section' && (
                                                <div className="space-y-2 pt-1">
                                                    <div className="flex items-center justify-between">
                                                        <span className="text-[10px] font-extrabold uppercase tracking-wider text-gray-600">
                                                            Select Target Courses & Sections:
                                                        </span>
                                                        {availableSections.length > 0 && (
                                                            <button
                                                                type="button"
                                                                onClick={() => {
                                                                    const allSelected =
                                                                        data.target_sections
                                                                            .length ===
                                                                        availableSections.length;
                                                                    setData(
                                                                        'target_sections',
                                                                        allSelected
                                                                            ? []
                                                                            : [...availableSections]
                                                                    );
                                                                    if (
                                                                        stepValidationErrors.length >
                                                                        0
                                                                    ) {
                                                                        setStepValidationErrors([]);
                                                                    }
                                                                }}
                                                                className="inline-flex min-h-[32px] items-center gap-1 rounded-md px-2 text-[11px] font-bold text-[#1B1F5C] hover:bg-gray-200/60 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                            >
                                                                {data.target_sections.length ===
                                                                availableSections.length ? (
                                                                    <>
                                                                        <Square
                                                                            className="h-3 w-3"
                                                                            aria-hidden="true"
                                                                        />
                                                                        <span>Clear All</span>
                                                                    </>
                                                                ) : (
                                                                    <>
                                                                        <CheckSquare
                                                                            className="h-3 w-3"
                                                                            aria-hidden="true"
                                                                        />
                                                                        <span>Select All</span>
                                                                    </>
                                                                )}
                                                            </button>
                                                        )}
                                                    </div>

                                                    {availableSections.length === 0 ? (
                                                        <p className="rounded-xl border border-amber-200 bg-amber-50 p-3 text-xs italic text-amber-800">
                                                            No student records with course/section found in Student Management yet. You can still publish as 'All Students'.
                                                        </p>
                                                    ) : (
                                                        <div className="grid max-h-48 grid-cols-1 gap-2 overflow-y-auto pr-1 sm:grid-cols-2">
                                                            {availableSections.map((sectionStr) => {
                                                                const isSelected =
                                                                    data.target_sections.includes(
                                                                        sectionStr
                                                                    );
                                                                return (
                                                                    <button
                                                                        key={sectionStr}
                                                                        type="button"
                                                                        aria-pressed={isSelected}
                                                                        onClick={() => {
                                                                            const updated =
                                                                                isSelected
                                                                                    ? data.target_sections.filter(
                                                                                          (s) =>
                                                                                              s !==
                                                                                              sectionStr
                                                                                      )
                                                                                    : [
                                                                                          ...data.target_sections,
                                                                                          sectionStr,
                                                                                      ];
                                                                            setData(
                                                                                'target_sections',
                                                                                updated
                                                                            );
                                                                            if (
                                                                                stepValidationErrors.length >
                                                                                0
                                                                            ) {
                                                                                setStepValidationErrors(
                                                                                    []
                                                                                );
                                                                            }
                                                                        }}
                                                                        className={`flex min-h-[38px] w-full items-center justify-between rounded-xl px-3.5 py-2 text-left text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                                            isSelected
                                                                                ? 'bg-[#1B1F5C] text-white'
                                                                                : 'border border-gray-200 bg-white text-gray-700 hover:bg-gray-50'
                                                                        }`}
                                                                    >
                                                                        <span className="truncate pr-2">
                                                                            {sectionStr}
                                                                        </span>
                                                                        {isSelected && (
                                                                            <Check
                                                                                className="h-4 w-4 shrink-0"
                                                                                aria-hidden="true"
                                                                            />
                                                                        )}
                                                                    </button>
                                                                );
                                                            })}
                                                        </div>
                                                    )}
                                                </div>
                                            )}
                                        </div>
                                    </div>

                                    <div className="space-y-3 rounded-2xl border border-gray-200/80 bg-[#F5F6FA]/70 p-4">
                                        <FormSwitch
                                            checked={isMultiDay}
                                            onCheckedChange={(checked: boolean) => {
                                                setIsMultiDay(checked);
                                                if (!checked) setData('event_end_date', '');
                                                if (stepValidationErrors.length > 0) {
                                                    setStepValidationErrors([]);
                                                }
                                            }}
                                            label="Enable Multi-Day Event (Span Range)"
                                        />

                                        <div
                                            className={`grid gap-3 ${
                                                isMultiDay
                                                    ? 'grid-cols-1 sm:grid-cols-2'
                                                    : 'grid-cols-1'
                                            }`}
                                        >
                                            <div>
                                                <label
                                                    htmlFor="event-date"
                                                    className="block text-[10px] font-bold uppercase tracking-wider text-gray-600"
                                                >
                                                    {isMultiDay ? 'Start Date *' : 'Event Date *'}
                                                </label>
                                                <input
                                                    id="event-date"
                                                    type="date"
                                                    required
                                                    value={data.event_date}
                                                    onChange={(e) => {
                                                        setData('event_date', e.target.value);
                                                        if (stepValidationErrors.length > 0) {
                                                            setStepValidationErrors([]);
                                                        }
                                                    }}
                                                    className="mt-1 min-h-[44px] w-full rounded-xl border border-gray-300 bg-white px-3.5 py-2 text-xs font-medium text-gray-900 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] sm:text-sm"
                                                />
                                            </div>

                                            {isMultiDay && (
                                                <div>
                                                    <label
                                                        htmlFor="event-end-date"
                                                        className="block text-[10px] font-bold uppercase tracking-wider text-gray-600"
                                                    >
                                                        End Date *
                                                    </label>
                                                    <input
                                                        id="event-end-date"
                                                        type="date"
                                                        required={isMultiDay}
                                                        min={data.event_date}
                                                        value={data.event_end_date || ''}
                                                        onChange={(e) => {
                                                            setData(
                                                                'event_end_date',
                                                                e.target.value
                                                            );
                                                            if (stepValidationErrors.length > 0) {
                                                                setStepValidationErrors([]);
                                                            }
                                                        }}
                                                        className="mt-1 min-h-[44px] w-full rounded-xl border border-gray-300 bg-white px-3.5 py-2 text-xs font-medium text-gray-900 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] sm:text-sm"
                                                    />
                                                </div>
                                            )}
                                        </div>
                                    </div>

                                    {isMultiDay && (
                                        <div className="space-y-3 rounded-2xl border border-gray-200/80 bg-[#F5F6FA]/70 p-4">
                                            <span className="block text-[10px] font-bold uppercase tracking-wider text-[#1B1F5C]">
                                                Multi-Day Schedule Mode
                                            </span>
                                            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                                                <button
                                                    type="button"
                                                    aria-pressed={scheduleMode === 'uniform'}
                                                    onClick={() => {
                                                        setScheduleMode('uniform');
                                                        if (stepValidationErrors.length > 0) {
                                                            setStepValidationErrors([]);
                                                        }
                                                    }}
                                                    className={`flex min-h-[44px] items-center justify-center gap-1.5 rounded-xl px-3 py-2 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                        scheduleMode === 'uniform'
                                                            ? 'bg-[#1B1F5C] text-white'
                                                            : 'border border-gray-200 bg-white text-gray-700 hover:bg-gray-50'
                                                    }`}
                                                >
                                                    Uniform Schedule (Same Hours Daily)
                                                </button>
                                                <button
                                                    type="button"
                                                    aria-pressed={scheduleMode === 'custom'}
                                                    onClick={() => {
                                                        setScheduleMode('custom');
                                                        if (stepValidationErrors.length > 0) {
                                                            setStepValidationErrors([]);
                                                        }
                                                    }}
                                                    className={`flex min-h-[44px] items-center justify-center gap-1.5 rounded-xl px-3 py-2 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                        scheduleMode === 'custom'
                                                            ? 'bg-[#1B1F5C] text-white'
                                                            : 'border border-gray-200 bg-white text-gray-700 hover:bg-gray-50'
                                                    }`}
                                                >
                                                    Custom Daily Schedule (Different Hours)
                                                </button>
                                            </div>
                                        </div>
                                    )}

                                    {/* UNIFORM CHECKPOINT RANGES CONFIGURATION */}
                                    {isMultiDay && scheduleMode === 'uniform' && (
                                        <div className="space-y-4 rounded-2xl border border-emerald-200/80 bg-emerald-50/40 p-4">
                                            <div className="flex flex-wrap items-center justify-between gap-2">
                                                <div className="flex items-center gap-2 text-xs font-bold text-emerald-900">
                                                    <Calendar className="h-4 w-4" aria-hidden="true" />
                                                    <span>
                                                        Uniform Checkpoint Ranges (Applied to All Days)
                                                    </span>
                                                </div>
                                                <FormSwitch
                                                    checked={Boolean(
                                                        uniformSchedule.has_afternoon ||
                                                            uniformSchedule.afternoon_enabled
                                                    )}
                                                    onCheckedChange={(checked: boolean) =>
                                                        handleUniformChange('has_afternoon', checked)
                                                    }
                                                    label="Enable Afternoon Session"
                                                />
                                            </div>

                                            <CheckpointRangeFields
                                                slot={uniformSchedule}
                                                scopeLabel="Uniform"
                                                onFieldChange={handleUniformChange}
                                            />
                                        </div>
                                    )}

                                    {/* CUSTOM CHECKPOINT RANGES PER SLOT/DAY */}
                                    {(!isMultiDay || scheduleMode === 'custom') &&
                                        data.schedules.map((schedule, dayIndex) => {
                                            const dayNumber = dayIndex + 1;
                                            return (
                                                <div
                                                    key={schedule.date}
                                                    className="space-y-4 rounded-2xl border border-emerald-200/80 bg-emerald-50/40 p-4"
                                                >
                                                    <div className="flex flex-wrap items-center justify-between gap-2">
                                                        <div className="flex items-center gap-2 text-xs font-bold text-emerald-900">
                                                            <Calendar
                                                                className="h-4 w-4"
                                                                aria-hidden="true"
                                                            />
                                                            <span>
                                                                {isMultiDay
                                                                    ? `Day ${dayNumber} (${formatDate(schedule.date)}) Schedule`
                                                                    : 'Event Schedule & Checkpoint Ranges'}
                                                            </span>
                                                        </div>

                                                        <button
                                                            type="button"
                                                            onClick={() => {
                                                                const updated = [...data.schedules];
                                                                updated[dayIndex].slots.push({
                                                                    ...DEFAULT_SLOT,
                                                                });
                                                                setData('schedules', updated);
                                                                if (
                                                                    stepValidationErrors.length > 0
                                                                ) {
                                                                    setStepValidationErrors([]);
                                                                }
                                                                validateTimeSlots(
                                                                    updated as any,
                                                                    setTimeValidationError
                                                                );
                                                            }}
                                                            className="inline-flex min-h-[38px] items-center gap-1 rounded-xl bg-emerald-700 px-3 py-1.5 text-xs font-bold text-white transition-colors hover:bg-emerald-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                        >
                                                            <Plus
                                                                className="h-4 w-4"
                                                                aria-hidden="true"
                                                            />
                                                            <span>Add Time Slot</span>
                                                        </button>
                                                    </div>

                                                    {schedule.slots.map((slot, slotIndex) => {
                                                        const slotHasAfternoon = Boolean(
                                                            slot.has_afternoon ||
                                                                slot.afternoon_enabled
                                                        );
                                                        return (
                                                            <div
                                                                key={slotIndex}
                                                                className="relative space-y-3 rounded-xl border border-gray-200 bg-white p-3.5 shadow-2xs"
                                                            >
                                                                <div className="flex flex-wrap items-center justify-between gap-2 border-b border-gray-100 pb-2">
                                                                    <span className="text-[11px] font-extrabold uppercase tracking-wider text-emerald-800">
                                                                        Slot {slotIndex + 1}{' '}
                                                                        Configuration
                                                                    </span>
                                                                    <div className="flex items-center gap-3">
                                                                        <FormSwitch
                                                                            checked={slotHasAfternoon}
                                                                            onCheckedChange={(
                                                                                checked: boolean
                                                                            ) => {
                                                                                const updated = [
                                                                                    ...data.schedules,
                                                                                ];
                                                                                const currentSlot =
                                                                                    updated[dayIndex]
                                                                                        .slots[
                                                                                        slotIndex
                                                                                    ];
                                                                                updated[
                                                                                    dayIndex
                                                                                ].slots[slotIndex] =
                                                                                    {
                                                                                        ...currentSlot,
                                                                                        has_afternoon:
                                                                                            checked,
                                                                                        afternoon_enabled:
                                                                                            checked,
                                                                                        afternoon_time_in_start:
                                                                                            checked
                                                                                                ? currentSlot.afternoon_time_in_start ||
                                                                                                  '13:00'
                                                                                                : '',
                                                                                        afternoon_time_in_end:
                                                                                            checked
                                                                                                ? currentSlot.afternoon_time_in_end ||
                                                                                                  '13:30'
                                                                                                : '',
                                                                                        afternoon_time_out_start:
                                                                                            checked
                                                                                                ? currentSlot.afternoon_time_out_start ||
                                                                                                  '16:30'
                                                                                                : '',
                                                                                        afternoon_time_out_end:
                                                                                            checked
                                                                                                ? currentSlot.afternoon_time_out_end ||
                                                                                                  '17:00'
                                                                                                : '',
                                                                                    };
                                                                                setData(
                                                                                    'schedules',
                                                                                    updated
                                                                                );
                                                                                if (
                                                                                    stepValidationErrors.length >
                                                                                    0
                                                                                ) {
                                                                                    setStepValidationErrors(
                                                                                        []
                                                                                    );
                                                                                }
                                                                                validateTimeSlots(
                                                                                    updated as any,
                                                                                    setTimeValidationError
                                                                                );
                                                                            }}
                                                                            label="Enable Afternoon Session"
                                                                        />
                                                                        {schedule.slots.length >
                                                                            1 && (
                                                                            <button
                                                                                type="button"
                                                                                onClick={() => {
                                                                                    const updated =
                                                                                        [
                                                                                            ...data.schedules,
                                                                                        ];
                                                                                    updated[
                                                                                        dayIndex
                                                                                    ].slots.splice(
                                                                                        slotIndex,
                                                                                        1
                                                                                    );
                                                                                    setData(
                                                                                        'schedules',
                                                                                        updated
                                                                                    );
                                                                                    if (
                                                                                        stepValidationErrors.length >
                                                                                        0
                                                                                    ) {
                                                                                        setStepValidationErrors(
                                                                                            []
                                                                                        );
                                                                                    }
                                                                                    validateTimeSlots(
                                                                                        updated as any,
                                                                                        setTimeValidationError
                                                                                    );
                                                                                }}
                                                                                className="inline-flex min-h-[32px] min-w-[32px] items-center justify-center rounded-lg text-gray-500 transition-colors hover:bg-rose-50 hover:text-rose-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                                                title="Remove Slot"
                                                                                aria-label={`Remove slot ${slotIndex + 1}`}
                                                                            >
                                                                                <X
                                                                                    className="h-4 w-4"
                                                                                    aria-hidden="true"
                                                                                />
                                                                            </button>
                                                                        )}
                                                                    </div>
                                                                </div>

                                                                <CheckpointRangeFields
                                                                    slot={slot}
                                                                    scopeLabel={`Day ${dayNumber} Slot ${slotIndex + 1}`}
                                                                    onFieldChange={(field, val) => {
                                                                        const updated = [
                                                                            ...data.schedules,
                                                                        ];
                                                                        updated[dayIndex].slots[
                                                                            slotIndex
                                                                        ][field] = val;
                                                                        setData(
                                                                            'schedules',
                                                                            updated
                                                                        );
                                                                        if (
                                                                            stepValidationErrors.length >
                                                                            0
                                                                        ) {
                                                                            setStepValidationErrors(
                                                                                []
                                                                            );
                                                                        }
                                                                        validateTimeSlots(
                                                                            updated as any,
                                                                            setTimeValidationError
                                                                        );
                                                                    }}
                                                                />
                                                            </div>
                                                        );
                                                    })}
                                                </div>
                                            );
                                        })}
                                </div>
                            )}

                            {/* STEP 2: VENUE & GEOFENCING */}
                            {currentStep === 2 && (
                                <div className="space-y-4">
                                    <div>
                                        <div className="flex flex-wrap items-center justify-between gap-2">
                                            <label
                                                htmlFor="event-location"
                                                className="block text-[10px] font-bold uppercase tracking-wider text-gray-600"
                                            >
                                                Venue Name <span className="text-rose-600">*</span>
                                            </label>
                                            {venues.length > 0 && (
                                                <div className="flex flex-wrap items-center justify-end gap-1.5">
                                                    <Building2
                                                        className="h-3.5 w-3.5 text-gray-500"
                                                        aria-hidden="true"
                                                    />
                                                    <span className="text-[10px] font-bold uppercase text-gray-500">
                                                        Saved Venues:
                                                    </span>
                                                    {venues.map((venue, idx) => (
                                                        <button
                                                            key={idx}
                                                            type="button"
                                                            onClick={() =>
                                                                handleApplyVenuePreset(venue)
                                                            }
                                                            className="min-h-[30px] rounded-lg border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 px-2.5 py-1 text-[11px] font-bold text-[#1B1F5C] transition-colors hover:bg-[#1B1F5C]/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                        >
                                                            {venue.location}
                                                        </button>
                                                    ))}
                                                </div>
                                            )}
                                        </div>

                                        <div className="mt-1 flex items-center gap-2">
                                            <input
                                                id="event-location"
                                                type="text"
                                                required
                                                value={data.location}
                                                onChange={(e) => {
                                                    setData('location', e.target.value);
                                                    setGeocodeConfirmation(null);
                                                    setGeocodeError(null);
                                                    if (stepValidationErrors.length > 0) {
                                                        setStepValidationErrors([]);
                                                    }
                                                }}
                                                onKeyDown={(e) => {
                                                    if (e.key === 'Enter') {
                                                        e.preventDefault();
                                                        geocodeVenueName();
                                                    }
                                                }}
                                                placeholder="e.g. MMSU Main Gym"
                                                className="min-h-[44px] w-full rounded-xl border border-gray-300 bg-white px-3.5 py-2 text-xs font-medium text-gray-900 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] sm:text-sm"
                                            />
                                            <button
                                                type="button"
                                                onClick={() => geocodeVenueName()}
                                                disabled={isSearchingLocation}
                                                className="inline-flex min-h-[44px] shrink-0 items-center justify-center gap-1.5 rounded-xl border border-[#1B1F5C]/20 bg-[#1B1F5C]/5 px-3.5 py-2.5 text-xs font-bold text-[#1B1F5C] transition-colors hover:bg-[#1B1F5C]/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-60"
                                                title="Locate Venue on Map"
                                                aria-label="Locate venue on map"
                                            >
                                                {isSearchingLocation ? (
                                                    <Loader2
                                                        className="h-4 w-4 animate-spin motion-reduce:animate-none"
                                                        aria-hidden="true"
                                                    />
                                                ) : (
                                                    <Search className="h-4 w-4" aria-hidden="true" />
                                                )}
                                                <span className="hidden sm:inline">Locate</span>
                                            </button>
                                        </div>
                                        {geocodeConfirmation && (
                                            <p
                                                role="status"
                                                className="mt-1.5 flex items-center gap-1.5 text-xs font-semibold text-emerald-700"
                                            >
                                                <CheckCircle2
                                                    className="h-4 w-4 shrink-0"
                                                    aria-hidden="true"
                                                />
                                                <span className="truncate">
                                                    Matched: {geocodeConfirmation}
                                                </span>
                                            </p>
                                        )}
                                        {geocodeError && (
                                            <p
                                                role="alert"
                                                className="mt-1.5 flex items-center gap-1.5 text-xs font-semibold text-rose-700"
                                            >
                                                <AlertCircle
                                                    className="h-4 w-4 shrink-0"
                                                    aria-hidden="true"
                                                />
                                                <span>{geocodeError}</span>
                                            </p>
                                        )}
                                    </div>

                                    <div className="space-y-3 rounded-2xl border border-gray-200/80 bg-[#F5F6FA]/70 p-4">
                                        <div className="flex flex-wrap items-center justify-between gap-2">
                                            <div className="flex items-center gap-2 text-xs font-bold text-[#1B1F5C]">
                                                <Navigation
                                                    className="h-4 w-4 text-[#F5A623]"
                                                    aria-hidden="true"
                                                />
                                                <span>GPS Geofence Location Boundary</span>
                                            </div>
                                            <FormSwitch
                                                checked={data.is_geofenced}
                                                onCheckedChange={(checked: boolean) => {
                                                    setData('is_geofenced', checked);
                                                    if (stepValidationErrors.length > 0) {
                                                        setStepValidationErrors([]);
                                                    }
                                                }}
                                                label="Enforce Geofence"
                                                activeClass="peer-checked:bg-[#1B1F5C]"
                                            />
                                        </div>

                                        {data.is_geofenced && (
                                            <div className="space-y-3 border-t border-gray-200 pt-3">
                                                <div className="grid grid-cols-2 gap-2 rounded-xl border border-gray-200 bg-white p-1">
                                                    <button
                                                        type="button"
                                                        aria-pressed={data.geofence_type === 'radius'}
                                                        onClick={() =>
                                                            setData('geofence_type', 'radius')
                                                        }
                                                        className={`flex min-h-[38px] items-center justify-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                            data.geofence_type === 'radius'
                                                                ? 'bg-[#1B1F5C] text-white'
                                                                : 'text-gray-700 hover:bg-gray-100'
                                                        }`}
                                                    >
                                                        <CircleDot
                                                            className="h-4 w-4 text-[#F5A623]"
                                                            aria-hidden="true"
                                                        />
                                                        <span>Circular Radius</span>
                                                    </button>
                                                    <button
                                                        type="button"
                                                        aria-pressed={
                                                            data.geofence_type === 'polygon'
                                                        }
                                                        onClick={() =>
                                                            setData('geofence_type', 'polygon')
                                                        }
                                                        className={`flex min-h-[38px] items-center justify-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-bold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] ${
                                                            data.geofence_type === 'polygon'
                                                                ? 'bg-[#1B1F5C] text-white'
                                                                : 'text-gray-700 hover:bg-gray-100'
                                                        }`}
                                                    >
                                                        <Hexagon
                                                            className="h-4 w-4 text-[#F5A623]"
                                                            aria-hidden="true"
                                                        />
                                                        <span>Hexagon Area</span>
                                                    </button>
                                                </div>

                                                {data.geofence_type === 'radius' && (
                                                    <div>
                                                        <div className="mb-1.5 flex items-center justify-between text-xs font-bold text-gray-700">
                                                            <label htmlFor="geofence-radius-slider">
                                                                Check-In Radius:
                                                            </label>
                                                            <span className="font-extrabold text-[#1B1F5C]">
                                                                {data.radius_meters} meters
                                                            </span>
                                                        </div>
                                                        <input
                                                            id="geofence-radius-slider"
                                                            type="range"
                                                            min={20}
                                                            max={500}
                                                            step={10}
                                                            value={data.radius_meters}
                                                            onChange={(e) =>
                                                                setData(
                                                                    'radius_meters',
                                                                    parseInt(e.target.value, 10)
                                                                )
                                                            }
                                                            className="w-full accent-[#1B1F5C] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                                        />
                                                    </div>
                                                )}

                                                <LocationPicker
                                                    mode={data.geofence_type}
                                                    latitude={data.latitude}
                                                    longitude={data.longitude}
                                                    radius={data.radius_meters}
                                                    polygon={data.geofence_polygon}
                                                    onChangeRadius={(lat, lng) =>
                                                        setData((prev) => ({
                                                            ...prev,
                                                            latitude: lat,
                                                            longitude: lng,
                                                        }))
                                                    }
                                                    onChangePolygon={(points) =>
                                                        setData('geofence_polygon', points)
                                                    }
                                                />
                                            </div>
                                        )}
                                    </div>
                                </div>
                            )}

                            {/* STEP 3: REVIEW & CONFIRMATION */}
                            {currentStep === 3 && (
                                <div className="space-y-4">
                                    <div className="space-y-3 rounded-2xl border border-gray-200 bg-[#F5F6FA]/70 p-4">
                                        <div className="flex items-center gap-2 text-sm font-bold text-[#1B1F5C]">
                                            <FileText
                                                className="h-4 w-4 text-[#F5A623]"
                                                aria-hidden="true"
                                            />
                                            <span>
                                                Event Configuration Summary ({data.schedules.length}{' '}
                                                {data.schedules.length === 1 ? 'Day' : 'Days'})
                                            </span>
                                        </div>

                                        <div className="grid grid-cols-1 gap-4 border-t border-gray-200 pt-3 text-xs sm:grid-cols-2 sm:text-sm">
                                            <div>
                                                <span className="block text-[10px] font-bold uppercase tracking-wider text-gray-500">
                                                    Title
                                                </span>
                                                <p className="mt-0.5 font-extrabold text-gray-900">
                                                    {data.title || 'Untitled Event'}
                                                </p>
                                            </div>
                                            <div>
                                                <span className="block text-[10px] font-bold uppercase tracking-wider text-gray-500">
                                                    Target Audience
                                                </span>
                                                <p className="mt-0.5 font-bold text-[#1B1F5C]">
                                                    {data.target_scope === 'all'
                                                        ? 'All Students (University-wide)'
                                                        : `${data.target_sections.length} Section(s) Selected`}
                                                </p>
                                            </div>
                                            <div>
                                                <span className="block text-[10px] font-bold uppercase tracking-wider text-gray-500">
                                                    Date Span
                                                </span>
                                                <p className="mt-0.5 font-bold text-gray-900">
                                                    {data.event_date
                                                        ? formatDate(data.event_date)
                                                        : 'Not set'}
                                                    {isMultiDay &&
                                                    data.event_end_date &&
                                                    data.event_end_date !== data.event_date
                                                        ? ` to ${formatDate(data.event_end_date)}`
                                                        : ''}
                                                </p>
                                            </div>
                                            <div>
                                                <span className="block text-[10px] font-bold uppercase tracking-wider text-gray-500">
                                                    Venue & Geofence
                                                </span>
                                                <p className="mt-0.5 font-bold text-gray-900">
                                                    {data.location || 'Unspecified Venue'} •{' '}
                                                    {data.is_geofenced
                                                        ? data.geofence_type === 'polygon'
                                                            ? 'Hexagon Area'
                                                            : `${data.radius_meters}m Radius`
                                                        : 'Location Free'}
                                                </p>
                                            </div>
                                        </div>
                                    </div>

                                    <FormSwitch
                                        checked={data.is_active}
                                        onCheckedChange={(checked: boolean) =>
                                            setData('is_active', checked)
                                        }
                                        label="Set Event as Active Immediately"
                                    />
                                </div>
                            )}
                        </form>

                        <footer className="flex items-center justify-between border-t border-gray-100 bg-white p-4 sm:p-5">
                            <div>
                                {currentStep > 1 && (
                                    <button
                                        key="wizard-back-btn"
                                        type="button"
                                        disabled={processing}
                                        onClick={() => {
                                            setStepValidationErrors([]);
                                            setCurrentStep((prev) => prev - 1);
                                        }}
                                        className="inline-flex min-h-[44px] items-center gap-1.5 rounded-xl border border-gray-300 px-4 py-2 text-xs font-bold text-gray-700 transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] sm:text-sm"
                                    >
                                        <ArrowLeft className="h-4 w-4" aria-hidden="true" />
                                        <span>Back</span>
                                    </button>
                                )}
                            </div>

                            <div className="flex items-center gap-2">
                                <button
                                    key="wizard-cancel-btn"
                                    type="button"
                                    disabled={processing}
                                    onClick={() => setIsFormOpen(false)}
                                    className="min-h-[44px] rounded-xl border border-gray-300 px-4 py-2 text-xs font-bold text-gray-700 transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] sm:text-sm"
                                >
                                    Cancel
                                </button>

                                {currentStep < 3 ? (
                                    <button
                                        key="wizard-next-btn"
                                        type="button"
                                        onClick={(e) => {
                                            e.preventDefault();
                                            e.stopPropagation();
                                            handleNextStep();
                                        }}
                                        className="inline-flex min-h-[44px] items-center gap-1.5 rounded-xl bg-[#1B1F5C] px-5 py-2 text-xs font-bold text-white shadow-xs transition-colors hover:bg-[#131644] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] sm:text-sm"
                                    >
                                        <span>Next Step</span>
                                        <ArrowRight
                                            className="h-4 w-4 text-[#F5A623]"
                                            aria-hidden="true"
                                        />
                                    </button>
                                ) : (
                                    <button
                                        key="wizard-submit-btn"
                                        type="button"
                                        onClick={handleExplicitSave}
                                        disabled={
                                            processing ||
                                            !stepThreeReady ||
                                            Boolean(timeValidationError)
                                        }
                                        className="inline-flex min-h-[44px] items-center gap-1.5 rounded-xl bg-[#1B1F5C] px-5 py-2 text-xs font-bold text-white shadow-xs transition-colors hover:bg-[#131644] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623] disabled:opacity-50 sm:text-sm"
                                    >
                                        {processing && (
                                            <Loader2
                                                className="h-4 w-4 animate-spin motion-reduce:animate-none"
                                                aria-hidden="true"
                                            />
                                        )}
                                        <span>
                                            {processing
                                                ? 'Saving...'
                                                : editingEvent
                                                  ? 'Save Changes'
                                                  : 'Create Event'}
                                        </span>
                                    </button>
                                )}
                            </div>
                        </footer>
                    </div>
                </div>
            )}

            <DeleteModal
                isOpen={isDeleteOpen}
                title="Delete Event"
                message={`Are you sure you want to delete "${selectedEvent?.title}"?`}
                onClose={() => setIsDeleteOpen(false)}
                onConfirm={confirmDelete}
                isDeleting={isDeleting}
            />
        </>
    );
}

function CheckpointRangeFields({
    slot,
    scopeLabel,
    onFieldChange,
}: {
    slot: CheckpointSlot;
    scopeLabel: string;
    onFieldChange: (field: string, value: string | boolean) => void;
}) {
    return (
        <div className="space-y-3">
            {/* Morning Session */}
            <div className="space-y-2 rounded-xl border border-blue-200/80 bg-blue-50/40 p-3">
                <div className="flex items-center gap-1.5 text-xs font-bold text-blue-900">
                    <Sun className="h-3.5 w-3.5 text-blue-600" aria-hidden="true" />
                    <span>Morning Session (Time-In & Time-Out Ranges)</span>
                </div>
                <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    <div>
                        <span className="block text-[10px] font-bold text-gray-700">
                            Morning Time-In Window (Start to Cut-Off){' '}
                            <span className="text-rose-600">*</span>
                        </span>
                        <div className="mt-1 flex items-center gap-2">
                            <input
                                type="time"
                                required
                                aria-label={`${scopeLabel} morning time-in start`}
                                value={slot.morning_time_in_start ?? ''}
                                onChange={(e) =>
                                    onFieldChange('morning_time_in_start', e.target.value)
                                }
                                className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-900 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            />
                            <span className="text-xs font-bold text-gray-500">to</span>
                            <input
                                type="time"
                                required
                                aria-label={`${scopeLabel} morning time-in cut-off`}
                                value={slot.morning_time_in_end ?? ''}
                                onChange={(e) =>
                                    onFieldChange('morning_time_in_end', e.target.value)
                                }
                                className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-900 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            />
                        </div>
                    </div>
                    <div>
                        <span className="block text-[10px] font-bold text-gray-700">
                            Morning Time-Out Window (Start to Cut-Off){' '}
                            <span className="text-rose-600">*</span>
                        </span>
                        <div className="mt-1 flex items-center gap-2">
                            <input
                                type="time"
                                required
                                aria-label={`${scopeLabel} morning time-out start`}
                                value={slot.morning_time_out_start ?? ''}
                                onChange={(e) =>
                                    onFieldChange('morning_time_out_start', e.target.value)
                                }
                                className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-900 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            />
                            <span className="text-xs font-bold text-gray-500">to</span>
                            <input
                                type="time"
                                required
                                aria-label={`${scopeLabel} morning time-out cut-off`}
                                value={slot.morning_time_out_end ?? ''}
                                onChange={(e) =>
                                    onFieldChange('morning_time_out_end', e.target.value)
                                }
                                className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-900 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                            />
                        </div>
                    </div>
                </div>
            </div>

            {/* Afternoon Session (Optional) */}
            {Boolean(slot.has_afternoon || slot.afternoon_enabled) && (
                <div className="space-y-2 rounded-xl border border-amber-200/80 bg-amber-50/40 p-3">
                    <div className="flex items-center gap-1.5 text-xs font-bold text-amber-900">
                        <Sunset className="h-3.5 w-3.5 text-amber-600" aria-hidden="true" />
                        <span>Afternoon Session (Time-In & Time-Out Ranges)</span>
                    </div>
                    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                        <div>
                            <span className="block text-[10px] font-bold text-gray-700">
                                Afternoon Time-In Window (Start to Cut-Off){' '}
                                <span className="text-rose-600">*</span>
                            </span>
                            <div className="mt-1 flex items-center gap-2">
                                <input
                                    type="time"
                                    required
                                    aria-label={`${scopeLabel} afternoon time-in start`}
                                    value={slot.afternoon_time_in_start ?? ''}
                                    onChange={(e) =>
                                        onFieldChange('afternoon_time_in_start', e.target.value)
                                    }
                                    className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-900 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                />
                                <span className="text-xs font-bold text-gray-500">to</span>
                                <input
                                    type="time"
                                    required
                                    aria-label={`${scopeLabel} afternoon time-in cut-off`}
                                    value={slot.afternoon_time_in_end ?? ''}
                                    onChange={(e) =>
                                        onFieldChange('afternoon_time_in_end', e.target.value)
                                    }
                                    className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-900 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                />
                            </div>
                        </div>
                        <div>
                            <span className="block text-[10px] font-bold text-gray-700">
                                Afternoon Time-Out Window (Start to Cut-Off){' '}
                                <span className="text-rose-600">*</span>
                            </span>
                            <div className="mt-1 flex items-center gap-2">
                                <input
                                    type="time"
                                    required
                                    aria-label={`${scopeLabel} afternoon time-out start`}
                                    value={slot.afternoon_time_out_start ?? ''}
                                    onChange={(e) =>
                                        onFieldChange('afternoon_time_out_start', e.target.value)
                                    }
                                    className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-900 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                />
                                <span className="text-xs font-bold text-gray-500">to</span>
                                <input
                                    type="time"
                                    required
                                    aria-label={`${scopeLabel} afternoon time-out cut-off`}
                                    value={slot.afternoon_time_out_end ?? ''}
                                    onChange={(e) =>
                                        onFieldChange('afternoon_time_out_end', e.target.value)
                                    }
                                    className="min-h-[38px] w-full rounded-xl border border-gray-300 bg-white px-3 py-1.5 text-xs font-medium text-gray-900 focus-visible:border-[#F5A623] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                                />
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}

function EmptyEventsState({
    activeTab,
    hasSearch,
    onClearSearch,
    onCreate,
}: {
    activeTab: TabKey;
    hasSearch: boolean;
    onClearSearch: () => void;
    onCreate: () => void;
}) {
    return (
        <div className="flex flex-col items-center justify-center space-y-2.5 px-6 py-14 text-center">
            <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-xl border border-[#1B1F5C]/15 bg-[#1B1F5C]/5 text-[#1B1F5C]">
                <CalendarX className="h-5 w-5" aria-hidden="true" />
            </div>
            <p className="text-sm font-bold text-gray-900">
                {hasSearch ? `No matching ${activeTab} events` : `No ${activeTab} events found`}
            </p>
            <p className="max-w-xs text-xs text-gray-500">
                {hasSearch
                    ? 'Try clearing your search term or switching to another status tab.'
                    : 'Create a new event session to configure attendance checkpoints and geofencing.'}
            </p>
            <div className="pt-1">
                {hasSearch ? (
                    <button
                        type="button"
                        onClick={onClearSearch}
                        className="inline-flex min-h-[38px] items-center gap-1.5 rounded-xl border border-gray-300 bg-white px-3.5 py-1.5 text-xs font-bold text-[#1B1F5C] transition-colors hover:bg-gray-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                    >
                        <RotateCcw className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                        <span>Clear Search</span>
                    </button>
                ) : (
                    <button
                        type="button"
                        onClick={onCreate}
                        className="inline-flex min-h-[38px] items-center gap-1.5 rounded-xl bg-[#1B1F5C] px-3.5 py-1.5 text-xs font-bold text-white transition-colors hover:bg-[#131644] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#F5A623]"
                    >
                        <Plus className="h-3.5 w-3.5 text-[#F5A623]" aria-hidden="true" />
                        <span>Create New Event</span>
                    </button>
                )}
            </div>
        </div>
    );
}

Events.layout = (page: React.ReactNode) => (
    <AdminLayout title="Events Management">{page}</AdminLayout>
);