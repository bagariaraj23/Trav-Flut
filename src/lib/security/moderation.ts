import { sanitizeInput } from '../security';

const PROFANITY_WORDS = [
  'damn',
  'hell',
  'crap',
  'ass',
  'bitch',
  'bastard',
  'fuck',
  'shit',
  'piss',
  'dick',
  'cock',
  'pussy',
  'whore',
  'slut',
  'fag',
  'nigger',
  'nigga',
  'retard',
  'idiot',
  'stupid',
];

function createProfanityRegex(words: string[]): RegExp {
  const escaped = words.map((word) => word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  const pattern = `\\b(${escaped.join('|')})\\b`;
  return new RegExp(pattern, 'gi');
}

const PROFANITY_REGEX = createProfanityRegex(PROFANITY_WORDS);

export interface ModerationResult {
  sanitized: string;
  hasProfanity: boolean;
  originalLength: number;
  sanitizedLength: number;
}

export function moderateContent(content: string): ModerationResult {
  const originalLength = content.length;
  let sanitized = sanitizeInput(content);
  const hasProfanity = PROFANITY_REGEX.test(sanitized);

  if (hasProfanity) {
    sanitized = sanitized.replace(PROFANITY_REGEX, (match) => '*'.repeat(match.length));
  }

  return {
    sanitized,
    hasProfanity,
    originalLength,
    sanitizedLength: sanitized.length,
  };
}

export function detectProfanity(content: string): boolean {
  return PROFANITY_REGEX.test(content);
}

