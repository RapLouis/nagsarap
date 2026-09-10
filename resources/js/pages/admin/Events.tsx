import React, { useState, useEffect } from 'react';
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
    Loader2
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
    time_in_start: string;
    time_in_end: string | null;
    time_out_start: string | null;
    time_out_end: string | null;
    approval_status: 'approved' | 'pending' | 'declined';
    is_active: boolean;
};

type Props = {
    events: {
        data: EventItem[];
        links: { url: string | null; label: string; active: boolean }[];
    };
    counts?: Record<TabKey, number>;
    filters: { search?: string; tab?: TabKey };
};

export default function Events({ 
    events, 
    counts = { ongoing: 0, upcoming: 0, completed: 0, pending: 0, declined: 0 }, 
    filters 
}: Props) {
    const [search, setSearch] = useState(filters.search || '');
    const [activeTab, setActiveTab] = useState<TabKey>(filters.tab || 'ongoing');

    // Toggles for Form Modal
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
        time_in_start: '',
        time_in_end: '',
        time_out_start: '',
        time_out_end: '',
        approval_status: 'approved' as 'approved' | 'pending' | 'declined',
        is_active: true,
    });

    useEffect(() => {
        if (successMessage) {
            const timer = setTimeout(() => setSuccessMessage(null), 5000);
            return () => clearTimeout(timer);
        }
    }, [successMessage]);

    // Nominatim Geocoding Auto-Search Handler
    const geocodeVenueName = async () => {
        if (!data.location || data.location.trim() === '') return;

        setIsSearchingLocation(true);
        try {
            const response = await fetch(
                `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(data.location)}`
            );
            const results = await response.json();

            if (results && results.length > 0) {
                const topMatch = results[0];
                const newLat = parseFloat(topMatch.lat);
                const newLng = parseFloat(topMatch.lon);

                // Re-calculate hexagon vertices centered on the searched location
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
            } else {
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
        router.get('/admin/events', { search, tab: tabKey }, { preserveState: true, replace: true });
    };

    const handleQuickStatusChange = (eventItem: EventItem, newStatus: 'approved' | 'declined') => {
        router.patch(`/admin/events/${eventItem.event_id}/status`, { approval_status: newStatus }, {
            preserveScroll: true,
            onSuccess: () => setSuccessMessage(`Event "${eventItem.title}" updated to ${newStatus}.`),
        });
    };

    const openCreateModal = () => {
        setEditingEvent(null);
        reset();
        clearErrors();

        // Preset Admin event creation to auto-approved
        setData((prev) => ({
            ...prev,
            approval_status: 'approved',
            is_active: true,
        }));

        setEnableTimeInCutoff(false);
        setEnableTimeOut(false);
        setEnableTimeOutCutoff(false);
        setIsFormOpen(true);
    };

    const openEditModal = (eventItem: EventItem) => {
        setEditingEvent(eventItem);
        clearErrors();

        // Safely parse saved numeric coordinates
        const savedLat = eventItem.latitude !== null && eventItem.latitude !== undefined 
            ? Number(eventItem.latitude) 
            : 18.1972;
        const savedLng = eventItem.longitude !== null && eventItem.longitude !== undefined 
            ? Number(eventItem.longitude) 
            : 120.5928;

        setData({
            title: eventItem.title,
            description: eventItem.description || '',
            location: eventItem.location || '',
            is_geofenced: Boolean(eventItem.is_geofenced),
            geofence_type: eventItem.geofence_type || 'radius',
            latitude: savedLat,
            longitude: savedLng,
            radius_meters: Number(eventItem.radius_meters) || 100,
            geofence_polygon: eventItem.geofence_polygon && eventItem.geofence_polygon.length >= 3 
                ? eventItem.geofence_polygon 
                : null,
            event_date: eventItem.event_date,
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
        if (editingEvent) {
            put(`/admin/events/${editingEvent.event_id}`, {
                onSuccess: () => {
                    setIsFormOpen(false);
                    setSuccessMessage(`Event "${data.title}" updated successfully.`);
                },
            });
        } else {
            post('/admin/events', {
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

    const TABS: { key: TabKey; label: string; activeColor: string }[] = [
        { key: 'ongoing', label: 'On Going', activeColor: 'text-blue-600 border-blue-600 bg-blue-50/50' },
        { key: 'upcoming', label: 'Upcoming', activeColor: 'text-emerald-600 border-emerald-600 bg-emerald-50/50' },
        { key: 'completed', label: 'Completed', activeColor: 'text-indigo-900 border-indigo-900 bg-indigo-50/50' },
        { key: 'pending', label: 'Pending Approval', activeColor: 'text-amber-600 border-amber-600 bg-amber-50/50' },
        { key: 'declined', label: 'Declined', activeColor: 'text-rose-600 border-rose-600 bg-rose-50/50' },
    ];

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
                        <button onClick={() => setSuccessMessage(null)} className="rounded-lg p-1 text-emerald-600 hover:bg-emerald-100">
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
                                        isActive
                                            ? `${tab.activeColor} border-b-2`
                                            : 'border-transparent text-gray-400 hover:text-gray-700'
                                    }`}
                                >
                                    <span>{tab.label}</span>
                                    <span className={`rounded-full px-2 py-0.5 text-[10px] ${
                                        isActive ? 'bg-white shadow-xs text-gray-800' : 'bg-gray-100 text-gray-500'
                                    }`}>
                                        {count}
                                    </span>
                                </button>
                            );
                        })}
                    </nav>
                </div>

                {/* SEARCH TOOLBAR */}
                <div className="flex items-center justify-between bg-white p-4 rounded-2xl border border-gray-100 shadow-xs">
                    <form onSubmit={(e) => { e.preventDefault(); router.get('/admin/events', { search, tab: activeTab }); }} className="relative w-full sm:w-72">
                        <input
                            type="text"
                            placeholder="Search event title, location..."
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                            className="w-full pl-9 pr-4 py-1.5 text-xs rounded-xl border border-gray-200 focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                        />
                        <Search className="absolute left-3 top-2 h-3.5 w-3.5 text-gray-400" />
                    </form>
                </div>

                {/* EVENTS TABLE */}
                <div className="overflow-hidden rounded-2xl border border-gray-100 bg-white shadow-xs">
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
                                events.data.map((item) => (
                                    <tr key={item.event_id} className="hover:bg-gray-50/50">
                                        <td className="px-6 py-4">
                                            <div className="font-bold text-[#1B1F5C]">{item.title}</div>
                                            <div className="text-[11px] text-gray-400 mt-0.5">
                                                {new Date(item.event_date).toLocaleDateString(undefined, {
                                                    month: 'short',
                                                    day: 'numeric',
                                                    year: 'numeric'
                                                })}
                                            </div>
                                        </td>
                                        <td className="px-6 py-4">
                                            <div className="flex items-center gap-1 font-semibold text-gray-700">
                                                <MapPin className="h-3.5 w-3.5 text-gray-400" />
                                                <span>{item.location || 'Unspecified Venue'}</span>
                                            </div>
                                            {item.is_geofenced ? (
                                                <span className="inline-flex items-center gap-1 text-[10px] text-blue-600 font-bold mt-0.5">
                                                    {item.geofence_type === 'polygon' ? <Hexagon className="h-3 w-3" /> : <CircleDot className="h-3 w-3" />}
                                                    <span>{item.geofence_type === 'polygon' ? 'Hexagon Polygon' : `Radius (${item.radius_meters}m)`}</span>
                                                </span>
                                            ) : (
                                                <span className="text-[10px] text-gray-400 block mt-0.5">Location Free</span>
                                            )}
                                        </td>
                                        <td className="px-6 py-4 text-gray-600">
                                            <div className="flex items-center gap-1.5 font-medium text-emerald-700">
                                                <LogIn className="h-3.5 w-3.5" />
                                                <span>{item.time_in_start}</span>
                                                {item.time_in_end && <span className="text-gray-400">- {item.time_in_end}</span>}
                                            </div>
                                        </td>
                                        <td className="px-6 py-4 text-gray-600">
                                            {item.time_out_start ? (
                                                <div className="flex items-center gap-1.5 font-medium text-amber-700">
                                                    <LogOut className="h-3.5 w-3.5" />
                                                    <span>{item.time_out_start}</span>
                                                    {item.time_out_end && <span className="text-gray-400">- {item.time_out_end}</span>}
                                                </div>
                                            ) : (
                                                <span className="text-gray-300">Disabled</span>
                                            )}
                                        </td>
                                        <td className="px-6 py-4">
                                            <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[10px] font-semibold ${
                                                item.is_active ? 'bg-emerald-50 text-emerald-700' : 'bg-gray-100 text-gray-500'
                                            }`}>
                                                <span className={`h-1.5 w-1.5 rounded-full ${item.is_active ? 'bg-emerald-500' : 'bg-gray-400'}`} />
                                                {item.is_active ? 'Active' : 'Inactive'}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4 text-right">
                                            <div className="flex items-center justify-end gap-1">
                                                {activeTab === 'pending' && (
                                                    <>
                                                        <button
                                                            onClick={() => handleQuickStatusChange(item, 'approved')}
                                                            className="rounded-lg p-1.5 text-emerald-600 hover:bg-emerald-50 transition"
                                                            title="Approve Event"
                                                        >
                                                            <Check className="h-4 w-4" />
                                                        </button>
                                                        <button
                                                            onClick={() => handleQuickStatusChange(item, 'declined')}
                                                            className="rounded-lg p-1.5 text-rose-600 hover:bg-rose-50 transition"
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
                                ))
                            ) : (
                                <tr>
                                    <td colSpan={6} className="px-6 py-12 text-center text-gray-400 space-y-2">
                                        <CalendarX className="h-8 w-8 mx-auto text-gray-300" />
                                        <p className="font-semibold text-xs">No {activeTab} events found.</p>
                                    </td>
                                </tr>
                            )}
                        </tbody>
                    </table>
                </div>
            </div>

            {/* FORM MODAL WITH CLEAN 2-COLUMN HEADER (NO APPROVAL SELECTOR) */}
            {isFormOpen && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4 backdrop-blur-xs">
                    <div className="w-full max-w-3xl rounded-3xl bg-white p-6 shadow-2xl transition-all max-h-[92vh] overflow-y-auto">
                        <div className="flex items-center justify-between border-b border-gray-100 pb-4">
                            <div className="flex items-center gap-2">
                                <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-[#1B1F5C]/10 text-[#1B1F5C]">
                                    <Calendar className="h-5 w-5" />
                                </div>
                                <h3 className="text-base font-bold text-[#0F172A]">
                                    {editingEvent ? 'Edit Event Details' : 'Create New Event'}
                                </h3>
                            </div>
                            <button onClick={() => setIsFormOpen(false)} className="rounded-lg p-1 text-gray-400 hover:bg-gray-100">
                                <X className="h-4 w-4" />
                            </button>
                        </div>

                        <form onSubmit={handleFormSubmit} className="mt-4 space-y-4 text-xs">
                            <div>
                                <label className="block font-bold uppercase tracking-wider text-gray-500">Event Title *</label>
                                <input
                                    type="text"
                                    required
                                    value={data.title}
                                    onChange={(e) => setData('title', e.target.value)}
                                    placeholder="e.g. University Sportsfest Day 1"
                                    className="mt-1 w-full rounded-xl border-gray-200 py-2 font-medium focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                />
                            </div>

                            <div className="grid grid-cols-2 gap-3">
                                <div>
                                    <label className="block font-bold uppercase tracking-wider text-gray-500">Date *</label>
                                    <input
                                        type="date"
                                        required
                                        value={data.event_date}
                                        onChange={(e) => setData('event_date', e.target.value)}
                                        className="mt-1 w-full rounded-xl border-gray-200 py-2 font-medium focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                    />
                                </div>
                                <div>
                                    <label className="block font-bold uppercase tracking-wider text-gray-500">Venue Name</label>
                                    <div className="mt-1 flex items-center gap-1.5">
                                        <input
                                            type="text"
                                            value={data.location}
                                            onChange={(e) => setData('location', e.target.value)}
                                            onKeyDown={(e) => {
                                                if (e.key === 'Enter') {
                                                    e.preventDefault();
                                                    geocodeVenueName();
                                                }
                                            }}
                                            placeholder="e.g. MMSU Main Gym"
                                            className="w-full rounded-xl border-gray-200 py-2 font-medium focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
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
                                </div>
                            </div>

                            {/* HYBRID GEOFENCE CONFIGURATION */}
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
                                        {/* MODE SELECTOR BUTTONS */}
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

                            {/* TIME IN CONFIG */}
                            <div className="rounded-2xl border border-emerald-100 bg-emerald-50/40 p-4 space-y-3">
                                <div className="flex items-center gap-1.5 font-bold text-emerald-800">
                                    <LogIn className="h-4 w-4" />
                                    <span>Time-In Configuration</span>
                                </div>
                                <div className="grid grid-cols-2 gap-3 items-end">
                                    <div>
                                        <label className="block font-bold text-gray-500">Start Time *</label>
                                        <input
                                            type="time"
                                            required
                                            value={data.time_in_start}
                                            onChange={(e) => setData('time_in_start', e.target.value)}
                                            className="mt-1 w-full rounded-xl border-gray-200 bg-white py-1.5 font-medium"
                                        />
                                    </div>
                                    {enableTimeInCutoff && (
                                        <div>
                                            <label className="block font-bold text-gray-500">End Time</label>
                                            <input
                                                type="time"
                                                value={data.time_in_end}
                                                onChange={(e) => setData('time_in_end', e.target.value)}
                                                className="mt-1 w-full rounded-xl border-gray-200 bg-white py-1.5 font-medium"
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

                            {/* TIME OUT CONFIG */}
                            <div className="rounded-2xl border border-amber-100 bg-amber-50/40 p-4 space-y-3">
                                <div className="flex items-center justify-between">
                                    <div className="flex items-center gap-1.5 font-bold text-amber-800">
                                        <LogOut className="h-4 w-4" />
                                        <span>Time-Out Configuration</span>
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
                                                <label className="block font-bold text-gray-500">Start Time</label>
                                                <input
                                                    type="time"
                                                    value={data.time_out_start}
                                                    onChange={(e) => setData('time_out_start', e.target.value)}
                                                    className="mt-1 w-full rounded-xl border-gray-200 bg-white py-1.5 font-medium"
                                                />
                                            </div>
                                            {enableTimeOutCutoff && (
                                                <div>
                                                    <label className="block font-bold text-gray-500">End Time</label>
                                                    <input
                                                        type="time"
                                                        value={data.time_out_end}
                                                        onChange={(e) => setData('time_out_end', e.target.value)}
                                                        className="mt-1 w-full rounded-xl border-gray-200 bg-white py-1.5 font-medium"
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

                            <div>
                                <label className="block font-bold uppercase tracking-wider text-gray-500">Description</label>
                                <textarea
                                    rows={2}
                                    value={data.description}
                                    onChange={(e) => setData('description', e.target.value)}
                                    placeholder="Optional details..."
                                    className="mt-1 w-full rounded-xl border-gray-200 py-2 font-medium"
                                />
                            </div>

                            <FormSwitch
                                checked={data.is_active}
                                onCheckedChange={(checked: boolean) => setData('is_active', checked)}
                                label="Set Event as Active Immediately"
                            />

                            <div className="mt-6 flex items-center justify-end gap-2 pt-2 border-t border-gray-100">
                                <button
                                    type="button"
                                    onClick={() => setIsFormOpen(false)}
                                    className="rounded-xl border border-gray-200 px-4 py-2 font-bold text-gray-600 hover:bg-gray-50"
                                >
                                    Cancel
                                </button>
                                <button
                                    type="submit"
                                    disabled={processing}
                                    className="rounded-xl bg-[#1B1F5C] px-5 py-2 font-bold text-white hover:bg-[#151848] disabled:opacity-50"
                                >
                                    {processing ? 'Saving...' : editingEvent ? 'Save Changes' : 'Create Event'}
                                </button>
                            </div>
                        </form>
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