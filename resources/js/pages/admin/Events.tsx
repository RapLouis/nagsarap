import React, { useEffect, useRef, useState } from 'react';
import { Head, Link, router, useForm } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import DeleteModal from '@/components/delete-modal';
import LocationPicker from '@/components/location-picker';
import FormSwitch from '@/components/ui/form-switch';
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
} from 'lucide-react';

type TabKey = 'ongoing' | 'upcoming' | 'completed' | 'pending' | 'declined';
type Point = { lat: number; lng: number };

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
    event_date: string;
    event_end_date: string | null;
    time_in_start: string;
    time_in_end: string | null;
    time_out_start: string | null;
    time_out_end: string | null;
    approval_status: 'approved' | 'pending' | 'declined';
    is_active: boolean;
};

type PageLink = { url: string | null; label: string; active: boolean };

type Props = {
    events: {
        data: EventItem[];
        links: PageLink[];
    };
    counts?: Record<TabKey, number>;
    filters: { search?: string; tab?: TabKey };
};

const TABS: { key: TabKey; label: string; activeColor: string }[] = [
    { key: 'ongoing', label: 'On Going', activeColor: 'text-blue-600 border-blue-600 bg-blue-50/50' },
    { key: 'upcoming', label: 'Upcoming', activeColor: 'text-emerald-600 border-emerald-600 bg-emerald-50/50' },
    { key: 'completed', label: 'Completed', activeColor: 'text-indigo-900 border-indigo-900 bg-indigo-50/50' },
    { key: 'pending', label: 'Pending Approval', activeColor: 'text-amber-600 border-amber-600 bg-amber-50/50' },
    { key: 'declined', label: 'Declined', activeColor: 'text-rose-600 border-rose-600 bg-rose-50/50' },
];

function relativeDateLabel(dateStr: string): string {
    const eventDate = new Date(dateStr + 'T00:00:00');
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const diffDays = Math.round((eventDate.getTime() - today.getTime()) / 86400000);

    if (diffDays === 0) return 'Today';
    if (diffDays === 1) return 'Tomorrow';
    if (diffDays === -1) return 'Yesterday';
    if (diffDays > 1 && diffDays <= 7) return `In ${diffDays} days`;
    if (diffDays < -1 && diffDays >= -7) return `${Math.abs(diffDays)} days ago`;
    return '';
}

function formatDate(dateStr: string): string {
    return new Date(dateStr + 'T00:00:00').toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
    });
}

export default function Events({
    events,
    counts = { ongoing: 0, upcoming: 0, completed: 0, pending: 0, declined: 0 },
    filters,
}: Props) {
    const [search, setSearch] = useState(filters.search || '');
    const [activeTab, setActiveTab] = useState<TabKey>(filters.tab || 'ongoing');
    const [isFiltering, setIsFiltering] = useState(false);
    const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const isFirstRun = useRef(true);

    // Wizard Flow States
    const [currentStep, setCurrentStep] = useState<number>(1);
    const [isMultiDay, setIsMultiDay] = useState(false);
    const [enableTimeInCutoff, setEnableTimeInCutoff] = useState(false);
    const [enableTimeOut, setEnableTimeOut] = useState(false);
    const [enableTimeOutCutoff, setEnableTimeOutCutoff] = useState(false);

    // Modal & Alert States
    const [isFormOpen, setIsFormOpen] = useState(false);
    const [editingEvent, setEditingEvent] = useState<EventItem | null>(null);
    const [isDeleteOpen, setIsDeleteOpen] = useState(false);
    const [selectedEvent, setSelectedEvent] = useState<EventItem | null>(null);
    const [isDeleting, setIsDeleting] = useState(false);
    const [successMessage, setSuccessMessage] = useState<string | null>(null);
    const [isSearchingLocation, setIsSearchingLocation] = useState(false);
    const [geocodeConfirmation, setGeocodeConfirmation] = useState<string | null>(null);
    const [quickActionEventId, setQuickActionEventId] = useState<number | null>(null);

    const { data, setData, post, put, processing, errors, reset, clearErrors } = useForm({
        title: '',
        description: '',
        location: '',
        is_geofenced: false,
        geofence_type: 'radius' as 'radius' | 'polygon',
        latitude: 18.1972 as number | null,
        longitude: 120.5928 as number | null,
        radius_meters: 100,
        geofence_polygon: null as Point[] | null,
        event_date: '',
        event_end_date: '' as string | null,
        time_in_start: '',
        time_in_end: '',
        time_out_start: '',
        time_out_end: '',
        approval_status: 'approved' as 'approved' | 'pending' | 'declined',
        is_active: true,
    });

    const hasFormErrors = Object.keys(errors).length > 0;

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
                },
            );
        }, 350);

        return () => {
            if (debounceRef.current) clearTimeout(debounceRef.current);
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [search]);

    const geocodeVenueName = async () => {
        if (!data.location || data.location.trim() === '') return;

        setIsSearchingLocation(true);
        setGeocodeConfirmation(null);
        try {
            const response = await fetch(
                `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(data.location)}`,
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
                    latitude: newLat,
                    longitude: newLng,
                    geofence_polygon: newHexagon,
                }));

                setGeocodeConfirmation(topMatch.display_name || `${newLat.toFixed(5)}, ${newLng.toFixed(5)}`);
            } else {
                setGeocodeConfirmation(null);
                alert('Location not found. Try adding a city or landmark (e.g., "MMSU Main Gym, Batac").');
            }
        } catch (error) {
            console.error('Error fetching venue geocode:', error);
        } finally {
            setIsSearchingLocation(false);
        }
    };

    const handleTabChange = (tabKey: TabKey) => {
        setActiveTab(tabKey);
        setIsFiltering(true);
        router.get(
            '/admin/events',
            { search, tab: tabKey },
            { preserveState: true, replace: true, onFinish: () => setIsFiltering(false) },
        );
    };

    const handleQuickStatusChange = (eventItem: EventItem, newStatus: 'approved' | 'declined') => {
        setQuickActionEventId(eventItem.event_id);
        router.patch(
            `/admin/events/${eventItem.event_id}/status`,
            { approval_status: newStatus },
            {
                preserveScroll: true,
                onSuccess: () => setSuccessMessage(`Event "${eventItem.title}" updated to ${newStatus}.`),
                onFinish: () => setQuickActionEventId(null),
            },
        );
    };

    const openCreateModal = () => {
        setEditingEvent(null);
        reset();
        clearErrors();
        setCurrentStep(1);
        setIsMultiDay(false);
        setGeocodeConfirmation(null);

        setData((prev) => ({
            ...prev,
            approval_status: 'approved',
            is_active: true,
            event_end_date: '',
        }));

        setEnableTimeInCutoff(false);
        setEnableTimeOut(false);
        setEnableTimeOutCutoff(false);
        setIsFormOpen(true);
    };

    const openEditModal = (eventItem: EventItem) => {
        setEditingEvent(eventItem);
        clearErrors();
        setCurrentStep(1);
        setGeocodeConfirmation(null);

        const hasMultiDay = Boolean(eventItem.event_end_date && eventItem.event_end_date !== eventItem.event_date);
        setIsMultiDay(hasMultiDay);

        const savedLat =
            eventItem.latitude !== null && eventItem.latitude !== undefined ? Number(eventItem.latitude) : 18.1972;
        const savedLng =
            eventItem.longitude !== null && eventItem.longitude !== undefined ? Number(eventItem.longitude) : 120.5928;

        setData({
            title: eventItem.title,
            description: eventItem.description || '',
            location: eventItem.location || '',
            is_geofenced: Boolean(eventItem.is_geofenced),
            geofence_type: eventItem.geofence_type || 'radius',
            latitude: savedLat,
            longitude: savedLng,
            radius_meters: Number(eventItem.radius_meters) || 100,
            geofence_polygon:
                eventItem.geofence_polygon && eventItem.geofence_polygon.length >= 3 ? eventItem.geofence_polygon : null,
            event_date: eventItem.event_date,
            event_end_date: eventItem.event_end_date || '',
            time_in_start: eventItem.time_in_start,
            time_in_end: eventItem.time_in_end || '',
            time_out_start: eventItem.time_out_start || '',
            time_out_end: eventItem.time_out_end || '',
            approval_status: eventItem.approval_status || 'approved',
            is_active: Boolean(eventItem.is_active),
        });

        setEnableTimeInCutoff(Boolean(eventItem.time_in_end));
        setEnableTimeOut(Boolean(eventItem.time_out_start));
        setEnableTimeOutCutoff(Boolean(eventItem.time_out_end));
        setIsFormOpen(true);
    };

    const handleFormSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        
        // Ensure event_end_date matches event_date if multi-day is disabled
        const submissionData = {
            ...data,
            event_end_date: isMultiDay ? data.event_end_date : null,
        };

        if (editingEvent) {
            put(`/admin/events/${editingEvent.event_id}`, {
                ...submissionData,
                preserveScroll: true,
                onSuccess: () => {
                    setIsFormOpen(false);
                    setSuccessMessage(`Event "${data.title}" updated successfully.`);
                },
            });
        } else {
            post('/admin/events', {
                ...submissionData,
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

    return (
        <>
            <Head title="Events Management" />

            <div className="p-6 space-y-6">
                {/* SUCCESS BANNER */}
                {successMessage && (
                    <div className="flex items-center justify-between rounded-2xl bg-emerald-50 border border-emerald-200 p-4 text-emerald-800 shadow-xs transition-all">
                        <div className="flex items-center gap-2 text-xs font-semibold">
                            <CheckCircle2 className="h-4 w-4 text-emerald-600 shrink-0" />
                            <span>{successMessage}</span>
                        </div>
                        <button
                            onClick={() => setSuccessMessage(null)}
                            className="rounded-lg p-1 text-emerald-600 hover:bg-emerald-100"
                            aria-label="Dismiss success message"
                        >
                            <X className="h-4 w-4" />
                        </button>
                    </div>
                )}

                {/* HEADER */}
                <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
                    <div>
                        <h2 className="text-xl font-bold text-gray-800">Events Management</h2>
                        <p className="text-xs text-gray-500">Configure attendance windows and hybrid venue geofencing boundaries</p>
                    </div>

                    <button
                        onClick={openCreateModal}
                        className="inline-flex items-center gap-2 rounded-xl bg-[#1B1F5C] px-4 py-2.5 text-xs font-bold text-white shadow-xs hover:bg-[#151848] transition active:scale-[0.98]"
                    >
                        <Plus className="h-4 w-4" />
                        <span>Create New Event</span>
                    </button>
                </div>

                {/* TAB NAVIGATION */}
                <div className="border-b border-gray-200 bg-white px-4 rounded-2xl shadow-xs">
                    <nav className="-mb-px flex space-x-4 overflow-x-auto">
                        {TABS.map((tab) => {
                            const isActive = activeTab === tab.key;
                            const count = counts?.[tab.key] ?? 0;
                            return (
                                <button
                                    key={tab.key}
                                    onClick={() => handleTabChange(tab.key)}
                                    className={`whitespace-nowrap py-3.5 px-3 border-b-2 font-bold text-xs transition-all flex items-center gap-2 ${
                                        isActive ? `${tab.activeColor} border-b-2` : 'border-transparent text-gray-400 hover:text-gray-700'
                                    }`}
                                >
                                    <span>{tab.label}</span>
                                    <span
                                        className={`rounded-full px-2 py-0.5 text-[10px] transition-opacity ${
                                            isActive ? 'bg-white shadow-xs text-gray-800' : 'bg-gray-100 text-gray-500'
                                        } ${isFiltering && isActive ? 'opacity-50' : 'opacity-100'}`}
                                    >
                                        {count}
                                    </span>
                                </button>
                            );
                        })}
                    </nav>
                </div>

                {/* SEARCH TOOLBAR */}
                <div className="flex items-center justify-between bg-white p-4 rounded-2xl border border-gray-100 shadow-xs">
                    <div className="relative w-full sm:w-72">
                        <input
                            type="text"
                            placeholder="Search event title, location..."
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                            className="w-full pl-9 pr-8 py-1.5 text-xs rounded-xl border border-gray-200 focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                            aria-label="Search events"
                        />
                        {isFiltering ? (
                            <Loader2 className="absolute left-3 top-2 h-3.5 w-3.5 text-gray-400 animate-spin" />
                        ) : (
                            <Search className="absolute left-3 top-2 h-3.5 w-3.5 text-gray-400" />
                        )}
                        {search && (
                            <button
                                onClick={() => setSearch('')}
                                className="absolute right-2.5 top-2 rounded-full p-0.5 text-gray-400 hover:bg-gray-100 hover:text-gray-600"
                                aria-label="Clear search"
                            >
                                <X className="h-3 w-3" />
                            </button>
                        )}
                    </div>
                </div>

                {/* EVENTS — DESKTOP TABLE */}
                <div className="hidden sm:block overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-xs">
                    <table className="w-full text-left text-sm text-gray-600">
                        <thead className="bg-gray-50 text-[11px] font-semibold uppercase text-gray-500">
                            <tr>
                                <th className="px-6 py-3">Event Details</th>
                                <th className="px-6 py-3">Geofence Type</th>
                                <th className="px-6 py-3">Time-In Window</th>
                                <th className="px-6 py-3">Time-Out Window</th>
                                <th className="px-6 py-3">Status</th>
                                <th className="px-6 py-3 text-right">Actions</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-100 text-xs">
                            {events.data.length > 0 ? (
                                events.data.map((item) => {
                                    const relLabel = relativeDateLabel(item.event_date);
                                    const isQuickActing = quickActionEventId === item.event_id;
                                    return (
                                        <tr
                                            key={item.event_id}
                                            className="hover:bg-gray-50/50 transition-colors"
                                        >
                                            {/* Clicking anywhere on these cells goes to the event show page */}
                                            <td className="px-6 py-4 max-w-[220px]">
                                                <Link href={`/admin/analytics/events/${item.event_id}`} className="block">
                                                    <div className="font-bold text-[#1B1F5C] truncate hover:underline" title={item.title}>
                                                        {item.title}
                                                    </div>
                                                    <div className="flex items-center gap-1.5 text-[11px] text-gray-400 mt-0.5">
                                                        <span>
                                                            {formatDate(item.event_date)}
                                                            {item.event_end_date && item.event_end_date !== item.event_date
                                                                ? ` - ${formatDate(item.event_end_date)}`
                                                                : ''}
                                                        </span>
                                                        {relLabel && (
                                                            <span className="rounded-full bg-gray-100 px-1.5 py-0.5 text-[10px] font-semibold text-gray-500">
                                                                {relLabel}
                                                            </span>
                                                        )}
                                                    </div>
                                                </Link>
                                            </td>

                                            <td className="px-6 py-4">
                                                <Link href={`/admin/analytics/events/${item.event_id}`} className="block">
                                                    <div className="flex items-center gap-1 font-semibold text-gray-700">
                                                        <MapPin className="h-3.5 w-3.5 text-gray-400 shrink-0" />
                                                        <span className="truncate max-w-[140px]" title={item.location || 'Unspecified Venue'}>
                                                            {item.location || 'Unspecified Venue'}
                                                        </span>
                                                    </div>
                                                    {item.is_geofenced ? (
                                                        <span className="inline-flex items-center gap-1 text-[10px] text-blue-600 font-bold mt-0.5">
                                                            {item.geofence_type === 'polygon' ? (
                                                                <Hexagon className="h-3 w-3" />
                                                            ) : (
                                                                <CircleDot className="h-3 w-3" />
                                                            )}
                                                            <span>
                                                                {item.geofence_type === 'polygon' ? 'Hexagon Polygon' : `Radius (${item.radius_meters}m)`}
                                                            </span>
                                                        </span>
                                                    ) : (
                                                        <span className="text-[10px] text-gray-400 block mt-0.5">Location Free</span>
                                                    )}
                                                </Link>
                                            </td>

                                            <td className="px-6 py-4 text-gray-600">
                                                <Link href={`/admin/analytics/events/${item.event_id}`} className="block">
                                                    <div className="flex items-center gap-1.5 font-medium text-emerald-700">
                                                        <LogIn className="h-3.5 w-3.5" />
                                                        <span>{item.time_in_start}</span>
                                                        {item.time_in_end && <span className="text-gray-400">- {item.time_in_end}</span>}
                                                    </div>
                                                </Link>
                                            </td>

                                            <td className="px-6 py-4 text-gray-600">
                                                <Link href={`/admin/analytics/events/${item.event_id}`} className="block">
                                                    {item.time_out_start ? (
                                                        <div className="flex items-center gap-1.5 font-medium text-amber-700">
                                                            <LogOut className="h-3.5 w-3.5" />
                                                            <span>{item.time_out_start}</span>
                                                            {item.time_out_end && <span className="text-gray-400">- {item.time_out_end}</span>}
                                                        </div>
                                                    ) : (
                                                        <span className="text-gray-300">Disabled</span>
                                                    )}
                                                </Link>
                                            </td>

                                            <td className="px-6 py-4">
                                                <Link href={`/admin/analytics/events/${item.event_id}`} className="block">
                                                    <span
                                                        className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[10px] font-semibold ${
                                                            item.is_active ? 'bg-emerald-50 text-emerald-700' : 'bg-gray-100 text-gray-500'
                                                        }`}
                                                    >
                                                        <span className={`h-1.5 w-1.5 rounded-full ${item.is_active ? 'bg-emerald-500' : 'bg-gray-400'}`} />
                                                        {item.is_active ? 'Active' : 'Inactive'}
                                                    </span>
                                                </Link>
                                            </td>

                                            {/* Action buttons stay interactive and do not trigger the row redirect */}
                                            <td className="px-6 py-4 text-right">
                                                <div className="flex items-center justify-end gap-1">
                                                    {activeTab === 'pending' && (
                                                        <>
                                                            <button
                                                                onClick={() => handleQuickStatusChange(item, 'approved')}
                                                                disabled={isQuickActing}
                                                                className="rounded-lg p-1.5 text-emerald-600 hover:bg-emerald-50 transition disabled:opacity-40"
                                                                title="Approve Event"
                                                            >
                                                                {isQuickActing ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                                                            </button>
                                                            <button
                                                                onClick={() => handleQuickStatusChange(item, 'declined')}
                                                                disabled={isQuickActing}
                                                                className="rounded-lg p-1.5 text-rose-600 hover:bg-rose-50 transition disabled:opacity-40"
                                                                title="Decline Event"
                                                            >
                                                                <XCircle className="h-4 w-4" />
                                                            </button>
                                                        </>
                                                    )}
                                                    <button
                                                        onClick={() => openEditModal(item)}
                                                        className="rounded-lg p-1.5 text-gray-400 hover:bg-gray-100 hover:text-gray-700 transition"
                                                        title="Edit Event"
                                                    >
                                                        <Pencil className="h-4 w-4" />
                                                    </button>
                                                    <button
                                                        onClick={() => promptDelete(item)}
                                                        className="rounded-lg p-1.5 text-gray-400 hover:bg-rose-50 hover:text-rose-600 transition"
                                                        title="Delete Event"
                                                    >
                                                        <Trash2 className="h-4 w-4" />
                                                    </button>
                                                </div>
                                            </td>
                                        </tr>
                                    );
                                })
                            ) : (
                                <tr>
                                    <td colSpan={6} className="px-6 py-12 text-center text-gray-400 space-y-3">
                                        <CalendarX className="h-8 w-8 mx-auto text-gray-300" />
                                        <p className="font-semibold text-xs">No {activeTab} events found.</p>
                                    </td>
                                </tr>
                            )}
                        </tbody>
                    </table>
                </div>

                {/* PAGINATION */}
                {events.links.length > 3 && (
                    <nav className="flex flex-wrap items-center justify-center gap-1" aria-label="Pagination">
                        {events.links.map((link, idx) => (
                            <Link
                                key={idx}
                                href={link.url ?? '#'}
                                preserveState
                                preserveScroll
                                className={`min-w-[2rem] rounded-lg px-3 py-1.5 text-center text-xs font-semibold transition ${
                                    link.active
                                        ? 'bg-[#1B1F5C] text-white'
                                        : link.url
                                          ? 'bg-white text-gray-600 border border-gray-200 hover:bg-gray-50'
                                          : 'bg-white text-gray-300 border border-gray-100 pointer-events-none'
                                }`}
                                dangerouslySetInnerHTML={{ __html: link.label }}
                            />
                        ))}
                    </nav>
                )}
            </div>

            {/* 3-STEP WIZARD FORM MODAL */}
            {isFormOpen && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-xs">
                    <div className="flex w-full max-w-3xl max-h-[92vh] flex-col rounded-3xl bg-white shadow-2xl transition-all">
                        {/* Modal Header */}
                        <div className="flex items-center justify-between border-b border-gray-100 p-6 pb-4">
                            <div className="flex items-center gap-2">
                                <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-[#1B1F5C]/10 text-[#1B1F5C]">
                                    <Calendar className="h-5 w-5" />
                                </div>
                                <div>
                                    <h3 className="text-base font-bold text-[#0F172A]">
                                        {editingEvent ? 'Edit Event Details' : 'Create New Event'}
                                    </h3>
                                    <p className="text-[11px] text-gray-400">Step {currentStep} of 3: {
                                        currentStep === 1 ? 'Event Basic Info & Schedule' :
                                        currentStep === 2 ? 'Venue & Geofencing' : 'Review & Confirmation'
                                    }</p>
                                </div>
                            </div>
                            <button
                                onClick={() => setIsFormOpen(false)}
                                className="rounded-lg p-1 text-gray-400 hover:bg-gray-100"
                                aria-label="Close"
                            >
                                <X className="h-4 w-4" />
                            </button>
                        </div>

                        {hasFormErrors && (
                            <div className="mx-6 mt-4 flex items-start gap-2 rounded-xl border border-rose-200 bg-rose-50 p-3 text-xs text-rose-700">
                                <AlertCircle className="h-4 w-4 shrink-0 mt-0.5" />
                                <div>
                                    <p className="font-bold">Please fix the following before saving:</p>
                                    <ul className="list-disc list-inside mt-1 space-y-0.5">
                                        {Object.values(errors).map((msg, i) => (
                                            <li key={i}>{msg}</li>
                                        ))}
                                    </ul>
                                </div>
                            </div>
                        )}

                        <form id="event-form" onSubmit={handleFormSubmit} className="flex-1 overflow-y-auto px-6 py-4 space-y-4 text-xs">
                            
                            {/* ================= STEP 1: EVENT DETAILS & SCHEDULES ================= */}
                            {currentStep === 1 && (
                                <div className="space-y-4 animate-fadeIn">
                                    <div>
                                        <label htmlFor="event-title" className="block font-bold uppercase tracking-wider text-gray-500">
                                            Event Title *
                                        </label>
                                        <input
                                            id="event-title"
                                            type="text"
                                            required
                                            value={data.title}
                                            onChange={(e) => setData('title', e.target.value)}
                                            placeholder="e.g. University Sportsfest Day 1"
                                            className="mt-1 w-full rounded-xl border border-gray-200 bg-white px-3 py-2 text-gray-800 font-medium focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                        />
                                    </div>

                                    <div>
                                        <label htmlFor="event-description" className="block font-bold uppercase tracking-wider text-gray-500">
                                            Description
                                        </label>
                                        <textarea
                                            id="event-description"
                                            rows={2}
                                            value={data.description}
                                            onChange={(e) => setData('description', e.target.value)}
                                            placeholder="Optional details..."
                                            className="mt-1 w-full rounded-xl border-gray-200 bg-white p-3 text-gray-800 font-medium"
                                        />
                                    </div>

                                    {/* Multi-Day Range Toggle */}
                                    <div className="rounded-2xl border border-gray-200 bg-gray-50/50 p-4 space-y-3">
                                        <FormSwitch
                                            checked={isMultiDay}
                                            onCheckedChange={(checked: boolean) => {
                                                setIsMultiDay(checked);
                                                if (!checked) setData('event_end_date', '');
                                            }}
                                            label="Enable Multi-Day Event (From Date to End Date)"
                                        />

                                        <div className={`grid ${isMultiDay ? 'grid-cols-2' : 'grid-cols-1'} gap-3`}>
                                            <div>
                                                <label htmlFor="event-date" className="block font-bold uppercase tracking-wider text-gray-500">
                                                    {isMultiDay ? 'Start Date *' : 'Event Date *'}
                                                </label>
                                                <input
                                                    id="event-date"
                                                    type="date"
                                                    required
                                                    value={data.event_date}
                                                    onChange={(e) => setData('event_date', e.target.value)}
                                                    className="mt-1 w-full rounded-xl border border-gray-200 bg-white px-3 py-2 text-gray-800 font-medium"
                                                />
                                            </div>

                                            {isMultiDay && (
                                                <div>
                                                    <label htmlFor="event-end-date" className="block font-bold uppercase tracking-wider text-gray-500">
                                                        End Date *
                                                    </label>
                                                    <input
                                                        id="event-end-date"
                                                        type="date"
                                                        required={isMultiDay}
                                                        value={data.event_end_date || ''}
                                                        onChange={(e) => setData('event_end_date', e.target.value)}
                                                        className="mt-1 w-full rounded-xl border border-gray-200 bg-white px-3 py-2 text-gray-800 font-medium"
                                                    />
                                                </div>
                                            )}
                                        </div>
                                    </div>

                                    {/* TIME-IN CONFIG */}
                                    <div className="rounded-2xl border border-emerald-100 bg-emerald-50/40 p-4 space-y-3">
                                        <div className="flex items-center gap-1.5 font-bold text-emerald-800">
                                            <LogIn className="h-4 w-4" />
                                            <span>{isMultiDay ? 'Day 1 Time-In Configuration' : 'Time-In Configuration'}</span>
                                        </div>
                                        <div className="grid grid-cols-2 gap-3 items-end">
                                            <div>
                                                <label htmlFor="time-in-start" className="block font-bold text-gray-500">Start Time *</label>
                                                <input
                                                    id="time-in-start"
                                                    type="time"
                                                    required
                                                    value={data.time_in_start}
                                                    onChange={(e) => setData('time_in_start', e.target.value)}
                                                    className="mt-1 w-full rounded-xl border border-gray-200 bg-white px-3 py-1.5 text-gray-800 font-medium"
                                                />
                                            </div>
                                            {enableTimeInCutoff && (
                                                <div>
                                                    <label htmlFor="time-in-end" className="block font-bold text-gray-500">Cutoff Time</label>
                                                    <input
                                                        id="time-in-end"
                                                        type="time"
                                                        value={data.time_in_end}
                                                        onChange={(e) => setData('time_in_end', e.target.value)}
                                                        className="mt-1 w-full rounded-xl border border-gray-200 bg-white px-3 py-1.5 text-gray-800 font-medium"
                                                    />
                                                </div>
                                            )}
                                        </div>
                                        <FormSwitch
                                            checked={enableTimeInCutoff}
                                            onCheckedChange={(checked: boolean) => {
                                                setEnableTimeInCutoff(checked);
                                                if (!checked) setData('time_in_end', '');
                                            }}
                                            label="Set Check-In Cutoff Time"
                                            activeClass="peer-checked:bg-emerald-600"
                                        />
                                    </div>

                                    {/* TIME-OUT CONFIG */}
                                    <div className="rounded-2xl border border-amber-100 bg-amber-50/40 p-4 space-y-3">
                                        <div className="flex items-center justify-between">
                                            <div className="flex items-center gap-1.5 font-bold text-amber-800">
                                                <LogOut className="h-4 w-4" />
                                                <span>{isMultiDay ? 'Day 2 Time-Out Configuration' : 'Time-Out Configuration'}</span>
                                            </div>
                                            <FormSwitch
                                                checked={enableTimeOut}
                                                onCheckedChange={(checked: boolean) => {
                                                    setEnableTimeOut(checked);
                                                    if (!checked) {
                                                        setData('time_out_start', '');
                                                        setData('time_out_end', '');
                                                        setEnableTimeOutCutoff(false);
                                                    }
                                                }}
                                                label="Enable Check-Out"
                                                activeClass="peer-checked:bg-amber-600"
                                            />
                                        </div>
                                        {enableTimeOut && (
                                            <div className="space-y-3 pt-2 border-t border-amber-200/50">
                                                <div className="grid grid-cols-2 gap-3 items-end">
                                                    <div>
                                                        <label htmlFor="time-out-start" className="block font-bold text-gray-500">Start Time</label>
                                                        <input
                                                            id="time-out-start"
                                                            type="time"
                                                            value={data.time_out_start}
                                                            onChange={(e) => setData('time_out_start', e.target.value)}
                                                            className="mt-1 w-full rounded-xl border border-gray-200 bg-white px-3 py-1.5 text-gray-800 font-medium"
                                                        />
                                                    </div>
                                                    {enableTimeOutCutoff && (
                                                        <div>
                                                            <label htmlFor="time-out-end" className="block font-bold text-gray-500">Cutoff Time</label>
                                                            <input
                                                                id="time-out-end"
                                                                type="time"
                                                                value={data.time_out_end}
                                                                onChange={(e) => setData('time_out_end', e.target.value)}
                                                                className="mt-1 w-full rounded-xl border border-gray-200 bg-white px-3 py-1.5 text-gray-800 font-medium"
                                                            />
                                                        </div>
                                                    )}
                                                </div>
                                                <FormSwitch
                                                    checked={enableTimeOutCutoff}
                                                    onCheckedChange={(checked: boolean) => {
                                                        setEnableTimeOutCutoff(checked);
                                                        if (!checked) setData('time_out_end', '');
                                                    }}
                                                    label="Set Check-Out Cutoff Time"
                                                    activeClass="peer-checked:bg-amber-600"
                                                />
                                            </div>
                                        )}
                                    </div>
                                </div>
                            )}

                            {/* ================= STEP 2: VENUE & GEOFENCING ================= */}
                            {currentStep === 2 && (
                                <div className="space-y-4 animate-fadeIn">
                                    <div>
                                        <label htmlFor="event-location" className="block font-bold uppercase tracking-wider text-gray-500">
                                            Venue Name
                                        </label>
                                        <div className="mt-1 flex items-center gap-1.5">
                                            <input
                                                id="event-location"
                                                type="text"
                                                value={data.location}
                                                onChange={(e) => {
                                                    setData('location', e.target.value);
                                                    setGeocodeConfirmation(null);
                                                }}
                                                onKeyDown={(e) => {
                                                    if (e.key === 'Enter') {
                                                        e.preventDefault();
                                                        geocodeVenueName();
                                                    }
                                                }}
                                                placeholder="e.g. MMSU Main Gym"
                                                className="w-full rounded-xl border border-gray-200 bg-white px-3 py-2 text-gray-800 font-medium focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                            />
                                            <button
                                                type="button"
                                                onClick={geocodeVenueName}
                                                disabled={isSearchingLocation}
                                                className="rounded-xl bg-blue-50 border border-blue-200 p-2 text-blue-700 hover:bg-blue-100 font-bold transition shrink-0"
                                                title="Locate Venue on Map"
                                            >
                                                {isSearchingLocation ? (
                                                    <Loader2 className="h-4 w-4 animate-spin text-blue-600" />
                                                ) : (
                                                    <Search className="h-4 w-4" />
                                                )}
                                            </button>
                                        </div>
                                        {geocodeConfirmation && (
                                            <p className="mt-1 flex items-center gap-1 text-[11px] text-emerald-600">
                                                <CheckCircle2 className="h-3 w-3 shrink-0" />
                                                <span className="truncate">Matched: {geocodeConfirmation}</span>
                                            </p>
                                        )}
                                    </div>

                                    {/* GEOFENCE CONFIGURATION */}
                                    <div className="rounded-2xl border border-blue-100 bg-blue-50/30 p-4 space-y-3">
                                        <div className="flex items-center justify-between">
                                            <div className="flex items-center gap-1.5 font-bold text-blue-900">
                                                <Navigation className="h-4 w-4" />
                                                <span>GPS Geofence Location Boundary</span>
                                            </div>
                                            <FormSwitch
                                                checked={data.is_geofenced}
                                                onCheckedChange={(checked: boolean) => setData('is_geofenced', checked)}
                                                label="Enforce Geofence"
                                                activeClass="peer-checked:bg-blue-600"
                                            />
                                        </div>

                                        {data.is_geofenced && (
                                            <div className="space-y-3 pt-2 border-t border-blue-100">
                                                <div className="grid grid-cols-2 gap-2 bg-blue-100/50 p-1 rounded-xl">
                                                    <button
                                                        type="button"
                                                        onClick={() => setData('geofence_type', 'radius')}
                                                        className={`py-1.5 rounded-lg font-bold transition flex items-center justify-center gap-1.5 ${
                                                            data.geofence_type === 'radius'
                                                                ? 'bg-white text-blue-900 shadow-xs'
                                                                : 'text-gray-500 hover:text-gray-800'
                                                        }`}
                                                    >
                                                        <CircleDot className="h-3.5 w-3.5" />
                                                        <span>Circular Radius</span>
                                                    </button>
                                                    <button
                                                        type="button"
                                                        onClick={() => setData('geofence_type', 'polygon')}
                                                        className={`py-1.5 rounded-lg font-bold transition flex items-center justify-center gap-1.5 ${
                                                            data.geofence_type === 'polygon'
                                                                ? 'bg-white text-blue-900 shadow-xs'
                                                                : 'text-gray-500 hover:text-gray-800'
                                                        }`}
                                                    >
                                                        <Hexagon className="h-3.5 w-3.5" />
                                                        <span>Hexagon Area</span>
                                                    </button>
                                                </div>

                                                {data.geofence_type === 'radius' && (
                                                    <div>
                                                        <div className="flex items-center justify-between text-[11px] font-bold text-gray-600 mb-1">
                                                            <span>Check-In Radius:</span>
                                                            <span className="text-blue-700">{data.radius_meters} meters</span>
                                                        </div>
                                                        <input
                                                            type="range"
                                                            min={20}
                                                            max={500}
                                                            step={10}
                                                            value={data.radius_meters}
                                                            onChange={(e) => setData('radius_meters', parseInt(e.target.value))}
                                                            className="w-full accent-[#1B1F5C]"
                                                        />
                                                    </div>
                                                )}

                                                <LocationPicker
                                                    mode={data.geofence_type}
                                                    latitude={data.latitude}
                                                    longitude={data.longitude}
                                                    radius={data.radius_meters}
                                                    polygon={data.geofence_polygon}
                                                    onChangeRadius={(lat, lng) => setData((prev) => ({ ...prev, latitude: lat, longitude: lng }))}
                                                    onChangePolygon={(points) => setData('geofence_polygon', points)}
                                                />
                                            </div>
                                        )}
                                    </div>
                                </div>
                            )}

                            {/* ================= STEP 3: REVIEW & CONFIRMATION ================= */}
                            {currentStep === 3 && (
                                <div className="space-y-4 animate-fadeIn">
                                    <div className="rounded-2xl border border-gray-200 bg-gray-50 p-4 space-y-3">
                                        <div className="flex items-center gap-1.5 font-bold text-[#1B1F5C]">
                                            <FileText className="h-4 w-4" />
                                            <span>Event Configuration Summary</span>
                                        </div>

                                        <div className="grid grid-cols-2 gap-3 text-xs pt-2 border-t border-gray-200">
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider">Title</span>
                                                <p className="font-bold text-gray-800 mt-0.5">{data.title || 'Untitled Event'}</p>
                                            </div>
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider">Date Span</span>
                                                <p className="font-bold text-gray-800 mt-0.5">
                                                    {data.event_date ? formatDate(data.event_date) : 'Not set'}
                                                    {data.event_end_date && data.event_end_date !== data.event_date
                                                        ? ` to ${formatDate(data.event_end_date)}`
                                                        : ''}
                                                </p>
                                            </div>
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider">Venue</span>
                                                <p className="font-bold text-gray-800 mt-0.5">{data.location || 'Unspecified Venue'}</p>
                                            </div>
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider">Geofence</span>
                                                <p className="font-bold text-gray-800 mt-0.5">
                                                    {data.is_geofenced ? `Enforced (${data.geofence_type})` : 'Disabled'}
                                                </p>
                                            </div>
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider">Time-In</span>
                                                <p className="font-bold text-emerald-700 mt-0.5">{data.time_in_start || 'Not set'}</p>
                                            </div>
                                            <div>
                                                <span className="text-gray-400 block font-bold uppercase tracking-wider">Time-Out</span>
                                                <p className="font-bold text-amber-700 mt-0.5">{data.time_out_start || 'Disabled'}</p>
                                            </div>
                                        </div>
                                    </div>

                                    <FormSwitch
                                        checked={data.is_active}
                                        onCheckedChange={(checked: boolean) => setData('is_active', checked)}
                                        label="Set Event as Active Immediately"
                                    />
                                </div>
                            )}
                        </form>

                        {/* WIZARD FOOTER NAVIGATION */}
                        <div className="flex items-center justify-between border-t border-gray-100 p-6 pt-4">
                            <div>
                                {currentStep > 1 && (
                                    <button
                                        type="button"
                                        onClick={() => setCurrentStep(currentStep - 1)}
                                        className="inline-flex items-center gap-1.5 rounded-xl border border-gray-200 px-4 py-2 font-bold text-gray-600 hover:bg-gray-50 text-xs"
                                    >
                                        <ArrowLeft className="h-3.5 w-3.5" />
                                        <span>Back</span>
                                    </button>
                                )}
                            </div>

                            <div className="flex items-center gap-2">
                                <button
                                    type="button"
                                    onClick={() => setIsFormOpen(false)}
                                    className="rounded-xl border border-gray-200 px-4 py-2 font-bold text-gray-600 hover:bg-gray-50 text-xs"
                                >
                                    Cancel
                                </button>

                                {currentStep < 3 ? (
                                    <button
                                        type="button"
                                        onClick={() => setCurrentStep(currentStep + 1)}
                                        className="inline-flex items-center gap-1.5 rounded-xl bg-[#1B1F5C] px-5 py-2 font-bold text-white hover:bg-[#151848] text-xs"
                                    >
                                        <span>Next Step</span>
                                        <ArrowRight className="h-3.5 w-3.5" />
                                    </button>
                                ) : (
                                    <button
                                        type="submit"
                                        form="event-form"
                                        disabled={processing}
                                        className="rounded-xl bg-[#1B1F5C] px-5 py-2 font-bold text-white hover:bg-[#151848] disabled:opacity-50 text-xs"
                                    >
                                        {processing ? 'Saving...' : editingEvent ? 'Save Changes' : 'Create Event'}
                                    </button>
                                )}
                            </div>
                        </div>
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

Events.layout = (page: React.ReactNode) => <AdminLayout title="Events Management">{page}</AdminLayout>; 