export type VoltageDropClassification = 'ok' | 'attention' | 'critical' | 'invalid';

export type VoltageDropInput = {
  systemVoltage: number;
  currentAmps: number;
  lengthMeters: number;
  crossSectionMm2: number;
};

export type VoltageDropResult = {
  dropVolts: number;
  dropPercent: number;
  classification: VoltageDropClassification;
  message: string;
};

const COPPER_RESISTIVITY = 0.017; // Ω·mm²/m (simplificado)

export function calculateVoltageDrop(input: VoltageDropInput): VoltageDropResult {
  const { systemVoltage, currentAmps, lengthMeters, crossSectionMm2 } = input;

  if (
    !Number.isFinite(systemVoltage) ||
    !Number.isFinite(currentAmps) ||
    !Number.isFinite(lengthMeters) ||
    !Number.isFinite(crossSectionMm2) ||
    systemVoltage <= 0 ||
    currentAmps < 0 ||
    lengthMeters < 0 ||
    crossSectionMm2 <= 0
  ) {
    return {
      dropVolts: 0,
      dropPercent: 0,
      classification: 'invalid',
      message: 'Preencha tensão, corrente, comprimento e bitola com valores positivos.',
    };
  }

  const dropVolts = (2 * lengthMeters * currentAmps * COPPER_RESISTIVITY) / crossSectionMm2;
  const dropPercent = (dropVolts / systemVoltage) * 100;

  let classification: VoltageDropClassification;
  let message: string;
  if (dropPercent <= 3) {
    classification = 'ok';
    message = 'Conforme (≤ 3%). Aceitável também para circuitos críticos.';
  } else if (dropPercent <= 10) {
    classification = 'attention';
    message = 'Atenção (entre 3% e 10%). Adequado apenas para circuitos não-críticos.';
  } else {
    classification = 'critical';
    message = 'Crítico (> 10%). Reavaliar bitola, comprimento ou tensão do sistema.';
  }

  return {
    dropVolts,
    dropPercent,
    classification,
    message,
  };
}
