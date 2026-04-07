export const en = {
  // Navigation
  nav: {
    dashboard: 'Dashboard',
    serviceOrders: 'Service Orders',
    clients: 'Clients',
    vessels: 'Vessels',
    marinas: 'Marinas',
    products: 'Products & Parts',
    inventory: 'Inventory',
    financial: 'Financial',
    reports: 'Reports',
    settings: 'Settings',
  },

  // Common
  common: {
    search: 'Search',
    filter: 'Filter',
    new: 'New',
    edit: 'Edit',
    save: 'Save',
    cancel: 'Cancel',
    delete: 'Delete',
    back: 'Back',
    viewAll: 'View all',
    noResults: 'No results found.',
    active: 'Active',
    inactive: 'Inactive',
    yes: 'Yes',
    no: 'No',
    loading: 'Loading...',
    actions: 'Actions',
    notes: 'Notes',
    documents: 'Documents',
    overview: 'Overview',
    details: 'Details',
    all: 'All',
    total: 'Total',
    date: 'Date',
    description: 'Description',
    status: 'Status',
    type: 'Type',
    amount: 'Amount',
    balance: 'Balance',
    company: 'Company',
    individual: 'Individual',
    orders: 'orders',
    open: 'open',
    docked: 'docked',
    created: 'Created',
    updated: 'Updated',
    saveChanges: 'Save Changes',
    saveSettings: 'Save Settings',
  },

  // Dashboard
  dashboard: {
    title: 'Dashboard',
    description: 'Overview of your nautical service operations',
    revenueMonth: 'Revenue ({month})',
    expensesMonth: 'Expenses ({month})',
    grossProfit: 'Gross Profit',
    openOrders: 'Open Orders',
    scheduledToday: '{count} scheduled today',
    pendingReceivables: 'Pending Receivables',
    pendingPayables: 'Pending Payables',
    activeTechnicians: 'Active Technicians',
    activeClients: 'Active Clients',
    revenueTrend: 'Revenue Trend',
    orderStatus: 'Order Status',
    recentServiceOrders: 'Recent Service Orders',
    noDataYet: 'No data available yet.',
    vsMar: '{value}% vs Mar',
  },

  // Service Orders
  serviceOrders: {
    title: 'Service Orders',
    description: 'Manage all service orders and field operations',
    newOrder: 'New Order',
    searchPlaceholder: 'Search orders, clients, vessels...',
    allStatuses: 'All Statuses',
    orderNumber: 'Order #',
    client: 'Client',
    vessel: 'Vessel',
    marina: 'Marina',
    priority: 'Priority',
    scheduled: 'Scheduled',
    notFound: 'Service order not found.',
    backToList: '← Back to list',
    startTimer: 'Start Timer',
    addPhoto: 'Add Photo',
    addPart: 'Add Part',
    complete: 'Complete',
    upload: 'Upload',
    // Tabs
    tabOverview: 'Overview',
    tabTechnical: 'Technical',
    tabTeam: 'Team & Time',
    tabParts: 'Parts',
    tabFinancial: 'Financial',
    tabFiles: 'Files',
    // Overview section
    clientAndVessel: 'Client & Vessel',
    requestedBy: 'Requested By',
    dockPosition: 'Dock Position',
    schedule: 'Schedule',
    scheduledStart: 'Scheduled Start',
    scheduledEnd: 'Scheduled End',
    checkIn: 'Check In',
    checkOut: 'Check Out',
    problemDescription: 'Problem Description',
    // Technical section
    initialFindings: 'Initial Findings',
    noFindingsYet: 'No findings recorded yet.',
    diagnosis: 'Diagnosis',
    pendingDiagnosis: 'Pending diagnosis.',
    solutionApplied: 'Solution Applied',
    // Team section
    timeEntries: 'Time Entries',
    noTimeEntries: 'No time entries recorded.',
    billable: 'Billable',
    nonBillable: 'Non-billable',
    // Parts section
    partsUsed: 'Parts Used',
    noPartsYet: 'No parts used yet.',
    product: 'Product',
    qty: 'Qty',
    unitPrice: 'Unit Price',
    // Financial section
    costBreakdown: 'Cost Breakdown',
    labor: 'Labor',
    parts: 'Parts',
    travel: 'Travel',
    subcontract: 'Subcontract',
    discount: 'Discount',
    tax: 'Tax',
    grandTotal: 'Grand Total',
    travelCalculation: 'Travel Calculation',
    origin: 'Origin',
    destination: 'Destination',
    distance: 'Distance',
    rate: 'Rate',
    technicians: 'Technicians',
    formula: 'Formula',
    travelTotal: 'Travel Total',
    // Files section
    photosAndDocs: 'Photos & Documents',
    noFilesYet: 'No files uploaded yet',
    dragAndDrop: 'Drag and drop or click upload to add photos and documents',
    prioritySuffix: 'Priority',
  },

  // Statuses
  status: {
    draft: 'Draft',
    scheduled: 'Scheduled',
    open: 'Open',
    in_progress: 'In Progress',
    awaiting_parts: 'Awaiting Parts',
    awaiting_client: 'Awaiting Client',
    completed: 'Completed',
    invoiced: 'Invoiced',
    cancelled: 'Cancelled',
  },

  // Priorities
  priority: {
    low: 'Low',
    normal: 'Normal',
    high: 'High',
    urgent: 'Urgent',
  },

  // Service types
  serviceType: {
    diagnosis: 'Diagnosis',
    repair: 'Repair',
    installation: 'Installation',
    preventive_maintenance: 'Preventive Maintenance',
    consulting: 'Consulting',
    engineering_project: 'Engineering Project',
    commissioning: 'Commissioning',
    inspection: 'Inspection',
  },

  // Payment statuses
  paymentStatus: {
    unpaid: 'Unpaid',
    partially_paid: 'Partial',
    paid: 'Paid',
    pending: 'Pending',
    overdue: 'Overdue',
    cancelled: 'Cancelled',
    not_invoiced: 'Not Invoiced',
  },

  // Clients
  clients: {
    title: 'Clients',
    description: 'Manage your client database',
    newClient: 'New Client',
    searchPlaceholder: 'Search clients by name, email, or document...',
    vessels: 'Vessels',
    serviceOrders: 'Service Orders',
    financial: 'Financial',
    noFinancialRecords: 'No financial records.',
    doc: 'Doc',
  },

  // Vessels
  vessels: {
    title: 'Vessels',
    description: 'Fleet registry and technical profiles',
    newVessel: 'New Vessel',
    searchPlaceholder: 'Search by vessel name, manufacturer, or owner...',
    vessel: 'Vessel',
    owner: 'Owner',
    engine: 'Engine',
    length: 'Length',
    year: 'Year',
    hullAndSpecs: 'Hull & Specs',
    hullId: 'Hull ID / Registration',
    beam: 'Beam',
    draft: 'Draft',
    propulsion: 'Propulsion',
    location: 'Location',
    shorePower: 'Shore Power',
    // Technical profile
    technicalProfile: 'Technical Profile',
    serviceHistory: 'Service History',
    engines: 'Engines',
    powerSystems: 'Power Systems',
    batteryBank: 'Battery Bank',
    inverterCharger: 'Inverter / Charger',
    navigationElectronics: 'Navigation Electronics',
    noNavElectronics: 'No navigation electronics documented.',
    electricalSystemNotes: 'Electrical System Notes',
    noMarina: 'No marina',
    notFound: 'Vessel not found.',
    noServiceHistory: 'No service history.',
  },

  // Marinas
  marinas: {
    title: 'Marinas',
    description: 'Marina directory and vessel locations',
    newMarina: 'New Marina',
    searchPlaceholder: 'Search marinas...',
    vesselsDocked: '{count} vessel(s) docked',
  },

  // Products
  products: {
    title: 'Products & Parts',
    description: 'Catalog of marine electrical components and parts',
    newProduct: 'New Product',
    searchPlaceholder: 'Search by name, SKU, or category...',
    category: 'Category',
    brand: 'Brand',
    stock: 'Stock',
    min: 'min',
    cost: 'Cost',
    salePrice: 'Sale Price',
  },

  // Inventory
  inventory: {
    title: 'Inventory',
    description: 'Stock movements and inventory control',
    recentMovements: 'Recent Stock Movements',
    by: 'By',
    movementType: {
      purchase: 'Purchase',
      service_usage: 'Service Usage',
      manual_adjustment: 'Adjustment',
      return: 'Return',
      transfer: 'Transfer',
    },
  },

  // Financial
  financial: {
    title: 'Financial',
    description: 'Receivables, payables, and cash flow',
    totalReceivables: 'Total Receivables',
    pendingCollection: 'Pending Collection',
    overdue: 'Overdue',
    pendingPayables: 'Pending Payables',
    cashFlow: 'Cash Flow',
    receivables: 'Receivables',
    payables: 'Payables',
    dueDate: 'Due Date',
    inflow: 'Inflow',
    outflow: 'Outflow',
  },

  // Reports
  reports: {
    title: 'Reports',
    description: 'Analytics and performance insights',
    collectedRevenue: 'Collected Revenue',
    avgOrderValue: 'Avg Order Value',
    billableHours: 'Billable Hours',
    totalOrders: 'Total Orders',
    technicianHours: 'Technician Hours',
    serviceTypeDistribution: 'Service Type Distribution',
    mostUsedParts: 'Most Used Parts',
    units: 'units',
  },

  // Settings
  settings: {
    title: 'Settings',
    description: 'Company configuration and system preferences',
    tabCompany: 'Company',
    tabTravel: 'Travel Costs',
    tabUsers: 'Users',
    tabLanguage: 'Language',
    tabCurrency: 'Currency',
    // Company
    companyInfo: 'Company Information',
    companyName: 'Company Name',
    cnpj: 'CNPJ',
    baseAddress: 'Base Address',
    latitude: 'Latitude',
    longitude: 'Longitude',
    phone: 'Phone',
    email: 'Email',
    // Travel
    travelSettings: 'Travel / Displacement Settings',
    defaultCostPerKm: 'Default Cost per KM',
    defaultHourlyRate: 'Default Hourly Rate',
    multiplyByTechnicians: 'Multiply travel cost by number of technicians',
    roundTrip: 'Calculate round trip (×2) by default',
    allowManualOverride: 'Allow manual travel cost override on service orders',
    // Users
    teamMembers: 'Team Members',
    userManagementNote: 'User management requires Lovable Cloud integration for authentication and role-based access control.',
    // Language
    languageSettings: 'Language Settings',
    selectLanguage: 'Select Language',
    languageNote: 'Change the interface language. All labels, navigation, and system messages will be updated.',
    // Currency
    currencySettings: 'Currency Settings',
    baseCurrency: 'Company Base Currency',
    displayCurrency: 'Display Currency',
    exchangeRates: 'Exchange Rates',
    exchangeRateNote: 'Exchange rates are used for display conversion. Original transaction values are always preserved.',
    lastUpdated: 'Last Updated',
    rateSource: 'Source',
    manual: 'Manual',
    addRate: 'Add Rate',
    from: 'From',
    to: 'To',
    rateValue: 'Rate',
    effectiveDate: 'Effective Date',
  },

  // Roles
  roles: {
    admin: 'Admin',
    technician: 'Technician',
    financial: 'Financial',
  },

  // Not found
  notFound: {
    title: '404',
    message: 'Oops! Page not found',
    backHome: 'Return to Home',
  },

  // Months
  months: {
    jan: 'Jan',
    feb: 'Feb',
    mar: 'Mar',
    apr: 'Apr',
    may: 'May',
    jun: 'Jun',
    jul: 'Jul',
    aug: 'Aug',
    sep: 'Sep',
    oct: 'Oct',
    nov: 'Nov',
    dec: 'Dec',
  },
};

// Recursive type that mirrors the structure but allows any string values
type StringifyLeaves<T> = {
  [K in keyof T]: T[K] extends string ? string : StringifyLeaves<T[K]>;
};

export type TranslationKeys = StringifyLeaves<typeof en>;
