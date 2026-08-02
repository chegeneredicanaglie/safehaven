import type { ResolvedFetchedEntity, ViewerCachedEntity } from '~/lib'

export type PartialEntity = { type: 'partial', entity: ViewerCachedEntity } & Pick<ResolvedFetchedEntity, 'category' | 'family' | 'tags'>

export type FullEntity = { type: 'full' } & ResolvedFetchedEntity

export function cancellable<Args extends unknown[], Return>(t: unknown, fn: (...args: Args) => Promise<Return>): (...args: Args) => Promise<Return | null> {
  let controller: AbortController | undefined

  return async (...args: Args): Promise<Return | null> => {
    if (controller) controller.abort()
    controller = new AbortController()
    const extendedArgs = [...args, controller.signal] as Args
    let result: Return
    try {
      result = await fn.call(t, ...extendedArgs)
    }
    catch (e) {
      if (e instanceof DOMException && e.name == 'AbortError') {
        return null
      }
      throw e
    }
    controller = undefined
    return result
  }
}
