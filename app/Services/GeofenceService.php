<?php

namespace App\Services;

class GeofenceService
{
    /**
     * Check whether a coordinate is inside a circular geofence.
     *
     * @return array{
     *     inside: bool,
     *     distance: float,
     *     radius: float
     * }
     */
    public function check(
        float $latitude,
        float $longitude,
        float $centerLatitude,
        float $centerLongitude,
        float $radiusMeters
    ): array {
        $distance = $this->distanceInMeters(
            $latitude,
            $longitude,
            $centerLatitude,
            $centerLongitude
        );

        return [
            'inside' => $distance <= $radiusMeters,
            'distance' => round($distance, 2),
            'radius' => $radiusMeters,
        ];
    }

    /**
     * Calculate distance between two GPS coordinates using the Haversine formula.
     */
    private function distanceInMeters(
        float $latitude1,
        float $longitude1,
        float $latitude2,
        float $longitude2
    ): float {
        $earthRadius = 6371000.0;

        $lat1 = deg2rad($latitude1);
        $lat2 = deg2rad($latitude2);

        $deltaLatitude = deg2rad($latitude2 - $latitude1);
        $deltaLongitude = deg2rad($longitude2 - $longitude1);

        $a =
            sin($deltaLatitude / 2) ** 2
            + cos($lat1)
            * cos($lat2)
            * sin($deltaLongitude / 2) ** 2;

        $a = min(1.0, max(0.0, $a));

        $c = 2 * atan2(
            sqrt($a),
            sqrt(1 - $a)
        );

        return $earthRadius * $c;
    }
}