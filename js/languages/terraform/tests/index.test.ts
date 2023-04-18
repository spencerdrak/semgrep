import { expect, test } from "@jest/globals";

import { ParserFactory } from "../src/index";

const parserPromise = ParserFactory();

test("it has a lang value", async () => {
  const parser = await parserPromise;
  expect(parser.getLang()).toBe(32);
});

test("it parses a pattern", async () => {
  const parser = await parserPromise;
  parser.parsePattern(false, "value = $X");
});

test("it parses a file", async () => {
  const parser = await parserPromise;
  parser.parseTarget("tests/test.tf");
});