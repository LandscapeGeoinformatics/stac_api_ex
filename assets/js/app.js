import '../css/app.css';
import 'maplibre-gl/dist/maplibre-gl.css';
import MaplibreMapHook from './maplibre_hook.js';
// Initialize maps on page load
import { initStacMaps } from './maplibre_hook.js';
window.Hooks = {
  MaplibreMapHook
};
document.addEventListener('DOMContentLoaded', initStacMaps);