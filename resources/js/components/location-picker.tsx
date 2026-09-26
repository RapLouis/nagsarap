import React, { useEffect, useState, useMemo } from 'react';
import { MapContainer, TileLayer, Marker, Circle, Polygon, useMapEvents, useMap } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';

import markerIcon from 'leaflet/dist/images/marker-icon.png';
import markerShadow from 'leaflet/dist/images/marker-shadow.png';

// Default Pin Icon Fix
const DefaultIcon = L.icon({
    iconUrl: markerIcon,
    shadowUrl: markerShadow,
    iconSize: [25, 41],
    iconAnchor: [12, 41],
});
L.Marker.prototype.options.icon = DefaultIcon;

// Vertex Handle Icon (Sleek 12px SVG Circle)
const SmallVertexIcon = L.divIcon({
    className: 'custom-vertex-marker',
    html: `<div style="
        width: 12px;
        height: 12px;
        background-color: #60A5FA;
        border: 2px solid #1E40AF;
        border-radius: 50%;
        cursor: grab;
        box-shadow: 0 1px 3px rgba(0,0,0,0.3);
    "></div>`,
    iconSize: [12, 12],
    iconAnchor: [6, 6],
});

// Center Pivot Anchor Icon (16px Gold Star/Crosshair for Polygon Repositioning)
const CenterPivotIcon = L.divIcon({
    className: 'custom-pivot-marker',
    html: `<div style="
        width: 18px;
        height: 18px;
        background-color: #F59E0B;
        border: 2px solid #FFFFFF;
        border-radius: 50%;
        cursor: move;
        box-shadow: 0 2px 4px rgba(0,0,0,0.4);
        display: flex;
        align-items: center;
        justify-content: center;
        color: white;
        font-weight: bold;
        font-size: 10px;
    ">✦</div>`,
    iconSize: [18, 18],
    iconAnchor: [9, 9],
});

type Point = { lat: number; lng: number };

type Props = {
    mode: 'radius' | 'polygon';
    latitude: number | null;
    longitude: number | null;
    radius: number;
    polygon: Point[] | null;
    onChangeRadius: (lat: number, lng: number) => void;
    onChangePolygon: (points: Point[]) => void;
};

// Generates 6 regular hexagon vertices
function generateHexagonPoints(centerLat: number, centerLng: number, radiusMeters: number): Point[] {
    const points: Point[] = [];
    const latOffset = radiusMeters / 111111;
    const lngOffset = radiusMeters / (111111 * Math.cos((centerLat * Math.PI) / 180));

    for (let i = 0; i < 6; i++) {
        const angle = (i * 60 * Math.PI) / 180;
        points.push({
            lat: centerLat + latOffset * Math.sin(angle),
            lng: centerLng + lngOffset * Math.cos(angle),
        });
    }
    return points;
}

// Calculate Polygon Centroid (Geometric Center)
function calculateCentroid(points: Point[]): [number, number] {
    if (!points || points.length === 0) return [18.187999, 120.577730];
    let latSum = 0;
    let lngSum = 0;
    points.forEach((p) => {
        latSum += p.lat;
        lngSum += p.lng;
    });
    return [latSum / points.length, lngSum / points.length];
}

// Compute Geodesic Surface Area in m² (Shoelace Formula approximation)
function calculatePolygonArea(points: Point[]): number {
    if (!points || points.length < 3) return 0;
    let area = 0;
    const numPoints = points.length;

    for (let i = 0; i < numPoints; i++) {
        const j = (i + 1) % numPoints;
        const p1 = points[i];
        const p2 = points[j];

        const x1 = (p1.lng * Math.PI * 6378137 * Math.cos((p1.lat * Math.PI) / 180)) / 180;
        const y1 = (p1.lat * Math.PI * 6378137) / 180;
        const x2 = (p2.lng * Math.PI * 6378137 * Math.cos((p2.lat * Math.PI) / 180)) / 180;
        const y2 = (p2.lat * Math.PI * 6378137) / 180;

        area += x1 * y2 - x2 * y1;
    }
    return Math.abs(area / 2);
}

// Smooth Camera Controller
function MapViewController({ center }: { center: [number, number] }) {
    const map = useMap();
    useEffect(() => {
        if (center[0] && center[1]) {
            map.flyTo(center, 18, { duration: 1.2 });
        }
    }, [center[0], center[1]]);
    return null;
}

function MapClickHandler({ onClick }: { onClick: (lat: number, lng: number) => void }) {
    useMapEvents({
        click(e) {
            onClick(e.latlng.lat, e.latlng.lng);
        },
    });
    return null;
}

export default function LocationPicker({
    mode,
    latitude,
    longitude,
    radius,
    polygon,
    onChangeRadius,
    onChangePolygon,
}: Props) {
    const centerLat = latitude || 18.187999;
    const centerLng = longitude || 120.577730;
    const center: [number, number] = [centerLat, centerLng];

    const [tileLayerType, setTileLayerType] = useState<'satellite' | 'street'>('satellite');

    // Auto-generate initial hexagon if in polygon mode
    useEffect(() => {
        if (mode === 'polygon' && (!polygon || polygon.length < 3)) {
            const initialHexagon = generateHexagonPoints(centerLat, centerLng, radius || 50);
            onChangePolygon(initialHexagon);
        }
    }, [mode]);

    // Calculate Polygon Centroid & Area
    const polygonCentroid = useMemo(() => {
        return polygon && polygon.length >= 3 ? calculateCentroid(polygon) : center;
    }, [polygon]);

    const surfaceArea = useMemo(() => {
        if (mode === 'radius') {
            return Math.round(Math.PI * Math.pow(radius, 2));
        }
        return polygon ? Math.round(calculatePolygonArea(polygon)) : 0;
    }, [mode, radius, polygon]);

    // Single Vertex Drag
    const handleVertexDrag = (index: number, e: L.LeafletEvent) => {
        const pos = e.target.getLatLng();
        if (!polygon) return;
        const updated = [...polygon];
        updated[index] = { lat: pos.lat, lng: pos.lng };
        onChangePolygon(updated);
    };

    // Center Anchor Delta Drag (Moves entire polygon without reshaping)
    const handleCenterPivotDrag = (e: L.LeafletEvent) => {
        if (!polygon || polygon.length === 0) return;
        const newPivot = e.target.getLatLng();
        const currentPivot = polygonCentroid;

        const deltaLat = newPivot.lat - currentPivot[0];
        const deltaLng = newPivot.lng - currentPivot[1];

        const shiftedPolygon = polygon.map((pt) => ({
            lat: pt.lat + deltaLat,
            lng: pt.lng + deltaLng,
        }));

        onChangePolygon(shiftedPolygon);
        onChangeRadius(newPivot.lat, newPivot.lng);
    };

    // Admin Browser GPS Auto-Locate
    const handleUseMyLocation = () => {
        if ('geolocation' in navigator) {
            navigator.geolocation.getCurrentPosition(
                (pos) => {
                    const userLat = pos.coords.latitude;
                    const userLng = pos.coords.longitude;

                    onChangeRadius(userLat, userLng);
                    if (mode === 'polygon') {
                        onChangePolygon(generateHexagonPoints(userLat, userLng, radius || 50));
                    }
                },
                (err) => alert(`Unable to fetch location: ${err.message}`),
                { enableHighAccuracy: true }
            );
        } else {
            alert('Geolocation is not supported by your browser.');
        }
    };

    return (
        <div className="space-y-2">
            {/* MAP OVERLAY HEADER CONTROLS */}
            <div className="flex items-center justify-between text-xs bg-gray-50 p-2 rounded-xl border border-gray-200">
                <div className="flex items-center gap-3">
                    <span className="font-bold text-gray-700">
                        Coverage Area: <span className="text-blue-600 font-extrabold">{surfaceArea.toLocaleString()} m²</span>
                    </span>
                </div>

                <div className="flex items-center gap-2">
                    {/* BASE MAP TOGGLE */}
                    <div className="flex bg-gray-200 p-0.5 rounded-lg text-[11px] font-semibold">
                        <button
                            type="button"
                            onClick={() => setTileLayerType('satellite')}
                            className={`px-2 py-0.5 rounded-md transition ${
                                tileLayerType === 'satellite' ? 'bg-white text-blue-900 shadow-xs font-bold' : 'text-gray-600'
                            }`}
                        >
                            Satellite
                        </button>
                        <button
                            type="button"
                            onClick={() => setTileLayerType('street')}
                            className={`px-2 py-0.5 rounded-md transition ${
                                tileLayerType === 'street' ? 'bg-white text-blue-900 shadow-xs font-bold' : 'text-gray-600'
                            }`}
                        >
                            Street Map
                        </button>
                    </div>

                    {/* CURRENT GPS BUTTON */}
                    <button
                        type="button"
                        onClick={handleUseMyLocation}
                        className="rounded-lg bg-blue-600 text-white px-2.5 py-1 font-bold text-[11px] hover:bg-blue-700 transition"
                    >
                        📍 My Location
                    </button>
                </div>
            </div>

            {/* LEAFLET CANVAS CONTAINER */}
            <div className="h-[420px] w-full rounded-2xl overflow-hidden border border-gray-200 shadow-inner relative z-0">
                <MapContainer center={center} zoom={18} maxZoom={22} className="h-full w-full">
                    <MapViewController center={center} />

                    {/* TILE PROVIDER LAYER */}
                    {tileLayerType === 'satellite' ? (
                        <TileLayer
                            attribution='&copy; <a href="https://www.esri.com/">Esri</a>'
                            url="https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
                            maxNativeZoom={19}
                            maxZoom={22}
                        />
                    ) : (
                        <TileLayer
                            attribution='&copy; <a href="https://carto.com/">CARTO</a>'
                            url="https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png"
                            maxNativeZoom={20}
                            maxZoom={22}
                        />
                    )}

                    {/* MODE 1: CIRCULAR RADIUS */}
                    {mode === 'radius' && (
                        <>
                            <MapClickHandler onClick={onChangeRadius} />
                            <Marker
                                position={center}
                                draggable={true}
                                eventHandlers={{
                                    dragend: (e) => {
                                        const pos = e.target.getLatLng();
                                        onChangeRadius(pos.lat, pos.lng);
                                    },
                                }}
                            />
                            <Circle
                                center={center}
                                radius={radius}
                                pathOptions={{ color: '#F59E0B', fillColor: '#FBBF24', fillOpacity: 0.35, weight: 2 }}
                            />
                        </>
                    )}

                    {/* MODE 2: CUSTOMIZABLE HEXAGON POLYGON */}
                    {mode === 'polygon' && polygon && polygon.length >= 3 && (
                        <>
                            <Polygon
                                positions={polygon.map((p) => [p.lat, p.lng])}
                                pathOptions={{ color: '#2563EB', fillColor: '#60A5FA', fillOpacity: 0.4, weight: 2 }}
                            />

                            {/* CENTER PIVOT ANCHOR (DRAG TO MOVE ENTIRE HEXAGON) */}
                            <Marker
                                position={polygonCentroid}
                                icon={CenterPivotIcon}
                                draggable={true}
                                eventHandlers={{
                                    drag: handleCenterPivotDrag,
                                    dragend: handleCenterPivotDrag,
                                }}
                            />

                            {/* INDIVIDUAL VERTEX HANDLES */}
                            {polygon.map((pt, idx) => (
                                <Marker
                                    key={`vertex-${idx}`}
                                    position={[pt.lat, pt.lng]}
                                    icon={SmallVertexIcon}
                                    draggable={true}
                                    eventHandlers={{
                                        drag: (e) => handleVertexDrag(idx, e),
                                        dragend: (e) => handleVertexDrag(idx, e),
                                    }}
                                />
                            ))}
                        </>
                    )}
                </MapContainer>
            </div>

            <div className="flex justify-between text-[10px] text-gray-500 font-medium px-1">
                <span>
                    {mode === 'radius'
                        ? 'Click map or drag center pin to position venue'
                        : 'Drag gold center anchor (✦) to move venue, or drag blue corner dots to reshape boundary'}
                </span>
                <span>Lat: {centerLat.toFixed(6)}, Lng: {centerLng.toFixed(6)}</span>
            </div>
        </div>
    );
}