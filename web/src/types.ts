export type DoorType = 'single' | 'double' | 'gate' | 'garage';

export interface Vec3 {
  x: number;
  y: number;
  z: number;
}

export interface Leaf {
  model: number | string;
  coords: Vec3;
  heading: number;
  [key: string]: unknown;
}

export interface JobAccess {
  name: string;
  grade: number | string;
}

export interface ItemAccess {
  name: string;
  metadata?: string;
  remove?: boolean;
}

export interface Access {
  mode: 'any' | 'all';
  public: boolean;
  admin: boolean;
  pin: boolean;
  jobs: JobAccess[];
  gangs: JobAccess[];
  identifiers: string[];
  items: ItemAccess[];
}

export interface Schedule {
  enabled: boolean;
  open: string;
  close: string;
  days: number[];
}

// Number fields stay as typed text while editing, converted on save
export interface Door {
  id: string;
  name: string;
  group?: string;
  type: DoorType;
  bucket: number | string;
  doors: Leaf[];
  locked: boolean;
  persist: boolean;
  autoLock: number | string;
  interactDistance: number | string;
  autoDistance: number | string;
  hideIndicator?: boolean;
  lockpick?: { enabled: boolean; difficulty: string };
  breach?: { enabled: boolean };
  alarm?: boolean;
  bell?: boolean;
  remote?: boolean;
  hackable?: boolean;
  schedule?: Schedule;
  sounds?: { lock?: string; unlock?: string };
  access: Access;
}

// A door as listed by the server
export interface DoorEntry extends Door {
  rev?: number;
  hasPin?: boolean;
  state?: boolean;
  tempAccess?: boolean;
  broken?: boolean;
}

export interface Group {
  name: string;
  label: string;
  count?: number;
}

export interface Template {
  name: string;
  access: Access;
}

export interface Pack {
  file: string;
  label: string;
  count?: number;
}

export interface SoundChoice {
  key: string;
  label: string;
}

export interface Defaults {
  locked?: boolean;
  persist?: boolean;
  autoLock?: number;
  mode?: 'any' | 'all';
  interact?: number;
  auto?: number;
}

export interface ReportError {
  id?: string;
  index?: number;
  err: string;
  detail?: string;
}
