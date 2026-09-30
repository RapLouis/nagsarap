import type { FaceLandmarker } from '@mediapipe/tasks-vision';

export type Direction = 'left' | 'right';
export type Landmark = { x: number; y: number };

// IMPORTANT: keep this equal to the installed @mediapipe/tasks-vision version
// (run `npm ls @mediapipe/tasks-vision`). A JS/WASM version mismatch causes odd failures.
export const MEDIAPIPE_VERSION = '0.10.21';
export const WASM_URL = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MEDIAPIPE_VERSION}/wasm`;
export const MODEL_URL =
    'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task';

export const VIDEO_CONSTRAINTS: MediaStreamConstraints = {
    video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'user' },
    audio: false,
};

/**
 * Direction convention: the camera image is UNMIRRORED and the direction is from the
 * PERSON'S point of view. Turning to your left gives a POSITIVE yaw ratio. Matches the
 * server-side convention in app.py. If left/right ever feels swapped on a real device,
 * flip these two values here — nowhere else needs to change.
 */
export const DIRECTION_SIGN: Record<Direction, 1 | -1> = { left: 1, right: -1 };

const NOSE_TIP = 1;
const LEFT_CHEEK = 234;
const RIGHT_CHEEK = 454;

// Face size/position, as a fraction of the video frame.
export const MIN_FACE_WIDTH = 0.22;
export const MAX_FACE_WIDTH = 0.6;
export const MAX_CENTER_OFFSET_X = 0.12;
export const MAX_CENTER_OFFSET_Y = 0.15;

export function calculateYaw(landmarks: Landmark[]): number {
    const nose = landmarks[NOSE_TIP];
    const left = landmarks[LEFT_CHEEK];
    const right = landmarks[RIGHT_CHEEK];
    if (!nose || !left || !right) return 0;

    const distanceLeft = Math.abs(nose.x - left.x);
    const distanceRight = Math.abs(nose.x - right.x);
    const total = distanceLeft + distanceRight;

    return total === 0 ? 0 : (distanceLeft - distanceRight) / total;
}

export function getFaceBounds(landmarks: Landmark[]) {
    let minX = 1;
    let maxX = 0;
    let minY = 1;
    let maxY = 0;

    for (const point of landmarks) {
        if (point.x < minX) minX = point.x;
        if (point.x > maxX) maxX = point.x;
        if (point.y < minY) minY = point.y;
        if (point.y > maxY) maxY = point.y;
    }

    return { width: maxX - minX, centerX: (minX + maxX) / 2, centerY: (minY + maxY) / 2 };
}

/** Returns a hint if the face is badly placed, or null if it is fine. */
export function getPlacementIssue(landmarks: Landmark[]): string | null {
    const { width, centerX, centerY } = getFaceBounds(landmarks);

    if (width < MIN_FACE_WIDTH) return 'Move closer to the camera.';
    if (width > MAX_FACE_WIDTH) return 'Move a little further from the camera.';
    if (Math.abs(centerX - 0.5) > MAX_CENTER_OFFSET_X || Math.abs(centerY - 0.5) > MAX_CENTER_OFFSET_Y) {
        return 'Center your face in the circle.';
    }
    return null;
}

/** Captures the current video frame (unmirrored) as a JPEG blob. */
export function captureFrame(
    video: HTMLVideoElement,
    options: { maxWidth?: number; maxHeight?: number; quality?: number } = {},
): Promise<Blob | null> {
    const { maxWidth = 640, maxHeight = 480, quality = 0.85 } = options;
    const canvas = document.createElement('canvas');
    canvas.width = Math.min(video.videoWidth || maxWidth, maxWidth);
    canvas.height = Math.min(video.videoHeight || maxHeight, maxHeight);

    const context = canvas.getContext('2d', { alpha: false });
    if (!context) return Promise.resolve(null);

    context.drawImage(video, 0, 0, canvas.width, canvas.height);

    return new Promise((resolve) => {
        canvas.toBlob((blob) => resolve(blob), 'image/jpeg', quality);
    });
}

export function randomDirection(): Direction {
    const bytes = new Uint8Array(1);
    crypto.getRandomValues(bytes);
    return bytes[0] % 2 === 0 ? 'left' : 'right';
}

export function describeCameraError(error: unknown): string {
    const name = (error as { name?: string })?.name;

    if (name === 'NotAllowedError' || name === 'SecurityError') {
        return 'Camera access was blocked. Allow camera permission in your browser settings, then reload the page.';
    }
    if (name === 'NotFoundError' || name === 'OverconstrainedError') {
        return 'No front camera was found on this device.';
    }
    if (name === 'NotReadableError') {
        return 'The camera is being used by another app. Close it and try again.';
    }
    if (error instanceof Error && error.message) return error.message;
    return 'Unable to access the camera.';
}

/**
 * The MediaPipe model (a few MB of WASM + weights) is expensive to load. A student may
 * open the check-in modal several times in a session (time-in, time-out, multiple
 * events), so the loaded model is cached for the lifetime of the tab instead of being
 * recreated — and closed — on every modal open/close.
 */
let sharedLandmarkerPromise: Promise<FaceLandmarker> | null = null;

async function createLandmarker(): Promise<FaceLandmarker> {
    const { FaceLandmarker, FilesetResolver } = await import('@mediapipe/tasks-vision');
    const vision = await FilesetResolver.forVisionTasks(WASM_URL);

    const create = (delegate: 'GPU' | 'CPU') =>
        FaceLandmarker.createFromOptions(vision, {
            baseOptions: { modelAssetPath: MODEL_URL, delegate },
            runningMode: 'VIDEO',
            numFaces: 2,
            minFaceDetectionConfidence: 0.5,
            minFacePresenceConfidence: 0.5,
            minTrackingConfidence: 0.5,
        });

    try {
        return await create('GPU');
    } catch (error) {
        console.warn('GPU delegate failed, falling back to CPU:', error);
        return await create('CPU');
    }
}

/** Returns the shared landmarker, creating it on first call. Never call .close() on it. */
export function getSharedLandmarker(): Promise<FaceLandmarker> {
    if (!sharedLandmarkerPromise) {
        sharedLandmarkerPromise = createLandmarker().catch((error) => {
            // Let the next caller retry instead of getting stuck with a rejected cache entry.
            sharedLandmarkerPromise = null;
            throw error;
        });
    }
    return sharedLandmarkerPromise;
}

/** Haversine distance in meters between two lat/lng points. */
export function distanceInMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const R = 6371000;
    const toRad = (deg: number) => deg * (Math.PI / 180);
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const a =
        Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/** Turns a GeolocationPositionError into a message that tells the student what to actually do. */
export function describeGeolocationError(error: GeolocationPositionError): string {
    switch (error.code) {
        case error.PERMISSION_DENIED:
            return 'Location access was denied. Enable location permission for this site in your browser settings, then try again.';
        case error.POSITION_UNAVAILABLE:
            return 'Your location could not be determined. Move to an area with a clearer GPS or network signal.';
        case error.TIMEOUT:
            return 'Getting your location took too long. Check your GPS/network signal and try again.';
        default:
            return 'Location access is required to check in. Please enable location permissions.';
    }
}