import React from 'react';

type FormSwitchProps = {
    id?: string;
    checked: boolean;
    onCheckedChange: (checked: boolean) => void;
    label?: string;
    activeClass?: string;
};

export default function FormSwitch({
    id,
    checked,
    onCheckedChange,
    label,
    activeClass = 'peer-checked:bg-[#1B1F5C]',
}: FormSwitchProps) {
    return (
        <label className="inline-flex items-center gap-2.5 cursor-pointer select-none">
            <div className="relative inline-flex items-center">
                <input
                    id={id}
                    type="checkbox"
                    checked={checked}
                    onChange={(e) => onCheckedChange(e.target.checked)}
                    className="sr-only peer"
                />
                <div
                    className={`h-5 w-9 rounded-full bg-gray-200 transition-colors duration-200 ease-in-out peer-focus:outline-none peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all ${activeClass}`}
                />
            </div>
            {label && <span className="text-xs font-semibold text-gray-700">{label}</span>}
        </label>
    );
}