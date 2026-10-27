/**
 * Errores de dominio. No conocen HTTP ni codigos de estado: traducirlos es
 * responsabilidad del adaptador (ADR-002).
 */
export class DomainError extends Error {
  constructor(
    message: string,
    readonly code: string,
  ) {
    super(message);
    this.name = 'DomainError';
  }
}

export class InvalidOrderError extends DomainError {
  constructor(message: string) {
    super(message, 'INVALID_ORDER');
    this.name = 'InvalidOrderError';
  }
}
