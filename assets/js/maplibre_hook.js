import maplibregl from 'maplibre-gl';
import * as turf from '@turf/turf';

function initMap(element) {
  const mapId = element.getAttribute('data-map-id');
  const dataAttr = element.getAttribute('data-geojson');

  if (!mapId || !dataAttr) return;

  let geojson = null;
  try {
    const raw = JSON.parse(dataAttr);
    if (raw && raw.type) {
      geojson = raw;
    }
  } catch (e) {
    console.error('Error parsing GeoJSON', e);
    return;
  }

  if (!geojson) return;

  const map = new maplibregl.Map({
    container: mapId,
    style: {
      version: 8,
      sources: {
        osm: {
          type: 'raster',
          tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
          tileSize: 256,
          attribution: '&copy; OpenStreetMap contributors'
        }
      },
      layers: [{ id: 'osm', type: 'raster', source: 'osm' }]
    },
    center: [25.7482, 58.3800],
    zoom: 7
  });

  map.on('load', function() {
    map.addSource(mapId + '-source', {
      type: 'geojson',
      data: geojson
    });

    map.addLayer({
      id: mapId + '-fill',
      type: 'fill',
      source: mapId + '-source',
      paint: {
        'fill-color': '#088',
        'fill-opacity': 0.3
      }
    });

    map.addLayer({
      id: mapId + '-outline',
      type: 'line',
      source: mapId + '-source',
      paint: {
        'line-color': '#088',
        'line-width': 2
      }
    });

    try {
      const bounds = turf.bbox(geojson);
      map.fitBounds(bounds, { padding: 50 });
    } catch (e) {
      console.warn('Could not fit bounds', e);
    }
  });
}

export function initStacMaps() {
  const mapElements = document.querySelectorAll('[data-map-id]');
  mapElements.forEach(initMap);
}

const MaplibreMapHook = {
  mounted() {
    initMap(this.el);
  }
};

export default MaplibreMapHook;