let deepSeekCallCount = 0;

export function incrementDeepSeekCallCount() {
  deepSeekCallCount += 1;
  return deepSeekCallCount;
}

export function getDeepSeekCallCount() {
  return deepSeekCallCount;
}
