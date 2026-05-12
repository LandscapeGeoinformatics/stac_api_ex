import MaplibreMapHook from './maplibre_hook.js';
import { initStacMaps } from './maplibre_hook.js';

window.Hooks = {
  MaplibreMapHook
};
document.addEventListener('DOMContentLoaded', initStacMaps);
