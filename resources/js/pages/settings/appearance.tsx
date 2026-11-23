import { Head } from '@inertiajs/react';
import AppearanceTabs from '@/components/appearance-tabs';
import Heading from '@/components/heading';
import { edit as editAppearance } from '@/routes/appearance';
import { Palette } from 'lucide-react';

export default function Appearance() {
    return (
        <>
            <Head title="Appearance Settings | 4ttnd Attendance System" />

            <h1 className="sr-only">Appearance settings</h1>

            <div className="w-full space-y-6 font-sans text-gray-900 antialiased">
                <div className="rounded-2xl bg-white p-6 sm:p-8 shadow-xs border border-gray-200/80 space-y-6">
                    <div className="flex items-center gap-2 border-b border-gray-100 pb-4">
                        <Palette className="h-5 w-5 text-[#1B1F5C]" aria-hidden="true" />
                        <Heading
                            variant="small"
                            title="Appearance Settings"
                            description="Customize theme appearance and view preferences for your session"
                        />
                    </div>

                    <div className="pt-2">
                        <AppearanceTabs />
                    </div>
                </div>
            </div>
        </>
    );
}

Appearance.layout = {
    breadcrumbs: [
        {
            title: 'Appearance settings',
            href: editAppearance(),
        },
    ],
};