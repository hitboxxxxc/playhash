/** Jest — testes 100% unitários/puros. NÃO usam emuladores nem credenciais. */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/src/tests'],
  testMatch: ['**/*.test.ts'],
  clearMocks: true,
  verbose: true,
};
