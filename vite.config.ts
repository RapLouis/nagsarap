import inertia from '@inertiajs/vite';
import { wayfinder } from '@laravel/vite-plugin-wayfinder';
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import laravel from 'laravel-vite-plugin';
import { bunny } from 'laravel-vite-plugin/fonts';
import { defineConfig } from 'vite';
import os from 'os';

// Helper to get local network IP automatically
function getLocalExternalIP() {
    const interfaces = os.networkInterfaces();
    let fallbackIp = 'localhost';

    for (const name of Object.keys(interfaces)) {
        for (const net of interfaces[name]!) {
            if (net.family === 'IPv4' && !net.internal) {
                if (net.address.startsWith('192.168.1.')) {
                    return net.address;
                }
                if (!net.address.startsWith('192.168.56.')) {
                    fallbackIp = net.address;
                }
            }
        }
    }
    return fallbackIp;
}

const localIp = getLocalExternalIP();

export default defineConfig({
    plugins: [
        laravel({
            input: ['resources/css/app.css', 'resources/js/app.tsx'],
            refresh: true,
            fonts: [
                bunny('Instrument Sans', {
                    weights: [400, 500, 600],
                }),
            ],
        }),
        inertia(),
        react({
            babel: {
                plugins: ['babel-plugin-react-compiler'],
            },
        }),
        tailwindcss(),
        wayfinder({
            formVariants: true,
        }),
    ],

    // Prevents Vite 8 / Rolldown from failing on MediaPipe CommonJS exports
    optimizeDeps: {
        exclude: ['@mediapipe/face_detection'],
        include: [
            '@tensorflow/tfjs-core',
            '@tensorflow/tfjs-backend-webgl',
            '@tensorflow-models/face-detection',
        ],
    },

    build: {
        commonjsOptions: {
            include: [/node_modules/],
        },
    },

    server: {
        host: '0.0.0.0',
        port: 5173,
    
        cors: {
            origin: [
                'http://localhost:8000',
                'http://127.0.0.1:8000',
                `http://${localIp}:8000`,
                'https://twiddly-unheatable-elenore.ngrok-free.dev',
            ],
        },
    
        hmr: {
            protocol: 'wss',
            host: 'twiddly-unheatable-elenore.ngrok-free.dev',
            clientPort: 443,
        },
    
        watch: {
            ignored: [
                '**/.agents/**',
                '**/.claude/**',
                '**/.cursor/**',
                '**/.junie/**',
                '**/vendor/**',
            ],
        },
    },
});