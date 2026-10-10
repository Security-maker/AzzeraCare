const svgPaths={
 home:'<path d="M3 10.8 12 3l9 7.8v9.7a1.5 1.5 0 0 1-1.5 1.5h-5v-7h-5v7h-5A1.5 1.5 0 0 1 3 20.5z"/>',
 planning:'<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M8 3v4M16 3v4M3 10h18"/>',
 interventions:'<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 3.5h6M8 8h8M8 12h8M8 16h5"/>',
 clients:'<circle cx="12" cy="8" r="3.2"/><path d="M5.5 21c.5-4 2.8-6 6.5-6s6 2 6.5 6"/>',
 sites:'<path d="M4 21V7l8-4 8 4v14M8 11h2M14 11h2M8 15h2M14 15h2M10 21v-3h4v3"/>',
 team:'<circle cx="9" cy="8" r="3"/><circle cx="17" cy="10" r="2.5"/><path d="M3 21c.4-4 2.6-6 6-6s5.6 2 6 6M14 16c3.7-.4 6 1.2 7 4"/>',
 quality:'<path d="m5 12 4 4 10-10"/><path d="M12 22a10 10 0 1 1 10-10"/>',
 logbook:'<path d="M5 4h14v16H5z"/><path d="M8 8h8M8 12h8M8 16h5"/>',
 docs:'<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v5h5M9 12h6M9 16h6"/>',
 requests:'<path d="M12 5v14M5 12h14"/>',
 profile:'<circle cx="12" cy="8" r="3.5"/><path d="M5 21c.5-4.2 3-6.3 7-6.3s6.5 2.1 7 6.3"/>',
 logout:'<path d="M10 4H5v16h5M14 8l4 4-4 4M8 12h10"/>',
 menu:'<path d="M4 7h16M4 12h16M4 17h16"/>',
 close:'<path d="m7 7 10 10M17 7 7 17"/>',
 bell:'<path d="M6 17h12l-1.5-2V10a4.5 4.5 0 0 0-9 0v5z"/><path d="M10 20h4"/>',
 photo:'<rect x="3" y="5" width="18" height="15" rx="3"/><circle cx="9" cy="11" r="2"/><path d="m21 16-5-4-7 7"/>',
 alert:'<path d="M12 3 2.8 20h18.4z"/><path d="M12 9v5M12 17h.01"/>',
 check:'<path d="m5 12 4 4 10-10"/>'
};
export function navIcon(key){return `<svg class="ui-icon" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${svgPaths[key]||svgPaths.interventions}</svg>`}
