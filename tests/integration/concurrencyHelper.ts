export async function runConcurrentCalls<T>(
    fn: () => Promise<T>,
    concurrency = 100,
    rounds = 1
): Promise<Array<T[]>> {
    const results: Array<T[]> = [];
    for (let r = 0; r < rounds; r++) {
        const calls: Array<Promise<T>> = [];
        for (let i = 0; i < concurrency; i++) {
            calls.push(fn());
        }
        const roundResults = await Promise.all(calls.map((p) => p.catch((e) => { throw e; })));
        results.push(roundResults);
    }
    return results;
}
