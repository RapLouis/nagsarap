import type { FaceLandmarker } from '@mediapipe/tasks-vision';

export type Direction = 'left' | 'right';
export type Landmark = { x: number; y: number };

// Ensure this matches the version of @mediapipe/tasks-vision installed in package.json
export const MEDIAPIPE_VERSION = '0.10.21';
export const WASM_URL = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MEDIAPIPE_VERSION}/wasm`;
export const MODEL_URL =
    'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task';

export const VIDEO_CONSTRAINTS: MediaStreamConstraints = {
    video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: 'user' },
    audio: false,
};

export const REFERENCE_VIDEO_CONSTRAINTS: MediaStreamConstraints = {
    video: { width: { ideal: 1280 }, height: { ideal: 720 }, facingMode: 'user' },
    audio: false,
};

export const DIRECTION_SIGN: Record<Direction, 1 | -1> = { left: 1, right: -1 };

const NOSE_TIP = 1;
const LEFT_CHEEK = 234;
const RIGHT_CHEEK = 454;

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
        return 'Camera access was blocked. Allow camera permission in your browser settings, then reload.';
    }
    if (name === 'NotFoundError' || name === 'OverconstrainedError') {
        return 'No front camera was found on this device.';
    }
    if (name === 'NotReadableError') {
        return 'The camera is being used by another application. Close it and try again.';
    }
    if (error instanceof Error && error.message) return error.message;
    return 'Unable to access the camera.';
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

/** Turns a GeolocationPositionError into a message for the student. */
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

/* -------------------------- Shared Landmarker Loader -------------------------- */

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

export function getSharedLandmarker(): Promise<FaceLandmarker> {
    if (!sharedLandmarkerPromise) {
        sharedLandmarkerPromise = createLandmarker().catch((error) => {
            sharedLandmarkerPromise = null;
            throw error;
        });
    }
    return sharedLandmarkerPromise;
}

/* ----------------------------- Screen Color Flash ---------------------------- */

export type FlashColor = 'red' | 'green' | 'blue';

export function isFlashColor(value: unknown): value is FlashColor {
    return value === 'red' || value === 'green' || value === 'blue';
}

export const FLASH_CSS_COLORS: Record<FlashColor, string> = {
    red: '#ff0000',
    green: '#00ff00',
    blue: '#0000ff',
};

export const FLASH_DURATION_MS = 700;
export const FLASH_CAPTURE_AT_MS = 450;

/* ------------------------------ Reference Capture ---------------------------- */

export const REFERENCE_CAPTURE_OPTIONS = { maxSide: 1280, quality: 0.92 };
export const LIVE_FRAME_OPTIONS = { maxSide: 640, quality: 0.8 };

export const REFERENCE_FRONTAL_YAW_MAX = 0.1;
export const REFERENCE_STABLE_FRAMES = 4;
export const REFERENCE_MIN_BRIGHTNESS = 60;
export const REFERENCE_MAX_BRIGHTNESS = 210;

export function captureFrameScaled(
    video: HTMLVideoElement,
    options: { maxSide?: number; quality?: number } = {},
): Promise<Blob | null> {
    const { maxSide = 640, quality = 0.8 } = options;
    const sourceWidth = video.videoWidth || 640;
    const sourceHeight = video.videoHeight || 480;
    const scale = Math.min(1, maxSide / Math.max(sourceWidth, sourceHeight));

    const canvas = document.createElement('canvas');
    canvas.width = Math.round(sourceWidth * scale);
    canvas.height = Math.round(sourceHeight * scale);

    const context = canvas.getContext('2d', { alpha: false });
    if (!context) return Promise.resolve(null);

    context.drawImage(video, 0, 0, canvas.width, canvas.height);

    return new Promise((resolve) => {
        canvas.toBlob((blob) => resolve(blob), 'image/jpeg', quality);
    });
}

let brightnessCanvas: HTMLCanvasElement | null = null;

export function measureBrightness(video: HTMLVideoElement): number | null {
    const width = 64;
    const height = 48;

    if (!brightnessCanvas) {
        brightnessCanvas = document.createElement('canvas');
        brightnessCanvas.width = width;
        brightnessCanvas.height = height;
    }

    const context = brightnessCanvas.getContext('2d', { willReadFrequently: true });
    if (!context) return null;

    try {
        context.drawImage(video, 0, 0, width, height);
        const { data } = context.getImageData(0, 0, width, height);

        let sum = 0;
        for (let i = 0; i < data.length; i += 4) {
            sum += data[i] * 0.299 + data[i + 1] * 0.587 + data[i + 2] * 0.114;
        }
        return sum / (data.length / 4);
    } catch {
        return null;
    }
}