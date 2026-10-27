// Cliente de base de datos (adaptador de infraestructura).
export interface QueryResult {
  readonly rows: readonly unknown[];
}

export const db = {
  async query(sql: string, params: readonly unknown[] = []): Promise<QueryResult> {
    // En la demo no hay BD real: lo que importa es DONDE vive este modulo.
    void sql;
    void params;
    return { rows: [] };
  },
};
