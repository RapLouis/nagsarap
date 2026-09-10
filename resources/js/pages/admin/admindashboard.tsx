import React, { useMemo, useState } from 'react';
import { Head } from '@inertiajs/react';
import AdminLayout from '@/layouts/admin-layout';
import { Users, Filter } from 'lucide-react';

type SectionCounts = Record<string, number>;
type DegreeGroup = {
    total: number;
    sections: SectionCounts;
};
type DegreesMap = Record<string, DegreeGroup>;

type Props = {
    totalStudents?: number;
    degrees?: DegreesMap;
};

const ALL = 'all';

export default function AdminDashboard({ totalStudents = 0, degrees = {} }: Props) {
    const [selectedDegree, setSelectedDegree] = useState<string>(ALL);
    const [selectedSection, setSelectedSection] = useState<string>(ALL);

    // List of available unique Degrees
    const availableDegrees = useMemo(() => Object.keys(degrees).sort(), [degrees]);

    // Dynamic list of Year & Section options based on chosen Degree
    const availableSections = useMemo(() => {
        const sections = new Set<string>();

        const degreeSource = selectedDegree === ALL
            ? Object.values(degrees)
            : degrees[selectedDegree]
                ? [degrees[selectedDegree]]
                : [];

        degreeSource.forEach((deg) => {
            Object.keys(deg.sections).forEach((sec) => sections.add(sec));
        });

        return Array.from(sections).sort((a, b) => 
            a.localeCompare(b, undefined, { numeric: true })
        );
    }, [degrees, selectedDegree]);

    // Computed real-time count
    const filteredCount = useMemo(() => {
        if (selectedDegree === ALL && selectedSection === ALL) {
            return totalStudents;
        }

        const degreeGroups = selectedDegree === ALL
            ? Object.values(degrees)
            : degrees[selectedDegree]
                ? [degrees[selectedDegree]]
                : [];

        if (selectedSection === ALL) {
            return degreeGroups.reduce((sum, deg) => sum + deg.total, 0);
        }

        let sum = 0;
        degreeGroups.forEach((deg) => {
            sum += deg.sections[selectedSection] ?? 0;
        });

        return sum;
    }, [degrees, totalStudents, selectedDegree, selectedSection]);

    const handleDegreeChange = (value: string) => {
        setSelectedDegree(value);
        setSelectedSection(ALL); // Reset section when course changes
    };

    return (
        <>
            <Head title="Admin Dashboard" />

            <div className="p-6">
                <div className="max-w-md rounded-2xl border border-gray-100 bg-white p-6 shadow-sm">
                    <div className="flex items-start justify-between gap-4">
                        <div className="flex-1 space-y-3">
                            <div className="flex items-center gap-1.5 text-xs font-semibold text-gray-400">
                                <Filter className="h-3.5 w-3.5 text-gray-400" />
                                <span>Registered Students Filter</span>
                            </div>

                            <div className="space-y-2">
                                {/* DEGREE / PROGRAM DROPDOWN */}
                                <div>
                                    <label className="block text-[10px] font-bold uppercase tracking-wider text-gray-400">
                                        Degree / Program
                                    </label>
                                    <select
                                        value={selectedDegree}
                                        onChange={(e) => handleDegreeChange(e.target.value)}
                                        className="mt-0.5 w-full rounded-lg border-gray-200 bg-gray-50/50 py-1.5 text-xs font-semibold text-[#1B1F5C] focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                    >
                                        <option value={ALL}>All Degrees & Programs</option>
                                        {availableDegrees.map((deg) => (
                                            <option key={deg} value={deg}>
                                                {deg}
                                            </option>
                                        ))}
                                    </select>
                                </div>

                                {/* YEAR & SECTION DROPDOWN */}
                                <div>
                                    <label className="block text-[10px] font-bold uppercase tracking-wider text-gray-400">
                                        Year & Section
                                    </label>
                                    <select
                                        value={selectedSection}
                                        onChange={(e) => setSelectedSection(e.target.value)}
                                        className="mt-0.5 w-full rounded-lg border-gray-200 bg-gray-50/50 py-1.5 text-xs font-semibold text-[#1B1F5C] focus:border-[#1B1F5C] focus:ring-[#1B1F5C]"
                                    >
                                        <option value={ALL}>All Years & Sections</option>
                                        {availableSections.map((sec) => (
                                            <option key={sec} value={sec}>
                                                {sec}
                                            </option>
                                        ))}
                                    </select>
                                </div>
                            </div>
                        </div>

                        {/* CARD ICON */}
                        <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-[#1B1F5C]/10 text-[#1B1F5C]">
                            <Users className="h-6 w-6" />
                        </div>
                    </div>

                    {/* COUNT RESULT */}
                    <div className="mt-5 border-t border-gray-100 pt-4">
                        <p className="text-[11px] font-medium text-gray-500">Total Students registered:</p>
                        <h3 className="text-3xl font-bold text-[#1B1F5C]">
                            {filteredCount.toLocaleString()}
                        </h3>
                    </div>
                </div>
            </div>
        </>
    );
}

AdminDashboard.layout = (page: React.ReactNode) => <AdminLayout title="Dashboard">{page}</AdminLayout>;