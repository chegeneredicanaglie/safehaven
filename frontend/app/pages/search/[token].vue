<template>
  <div class="h-full flex flex-col">
    <ViewerNavbar
      :token="token"
      :show-category-switcher="false"
      :show-search="false"
      :show-family-switcher="false"
      :show-map-button="state.permissions?.can_access_entity"
      :show-search-button="false"
    />

    <Card
      class="m-2 p-2"
    >
      <template #header>
        <div class="flex flex-col gap-1">
          <span class="text-2xl font-bold">
            {{ $t('page.search.token.search') }}
          </span>
          <span
            v-if="state.permissions?.can_add_comment && !state.permissions?.can_access_entity"
            class="text-muted-color"
          >
            {{ $t('page.search.token.addCommentHint') }}
          </span>
        </div>
      </template>

      <template #content>
        <form @submit.prevent="submitSearch">
          <div class="hidden sm:block">
            <InputGroup>
              <InputText
                v-model="query"
                :placeholder="$t('page.search.token.searchPlaceholder')
                  + (state.permissions?.can_list_without_query ? '' : $t('page.search.token.minChars'))"
              />

              <Button
                type="button"
                severity="secondary"
                :label="state.activeFamily.title"
                @click="showFamilySwitcher"
              >
                <template #icon>
                  <AppIcon
                    :icon-name="state.activeFamily.icon_hash!"
                    dynamic
                    class="mr-1"
                    size="20px"
                  />
                </template>
              </Button>

              <Button
                type="button"
                severity="warn"
                :label="$t('page.search.token.filters')"
                @click="showCriteriasModal()"
              >
                <template #icon>
                  <AppIcon
                    class="mr-1"
                    icon-name="filter"
                  />
                </template>
              </Button>

              <Button type="submit">
                <template #icon>
                  <AppIcon icon-name="search" />
                </template>
              </Button>
            </InputGroup>
          </div>
          <div class="sm:hidden flex flex-col justify-end items-end gap-2">
            <InputGroup>
              <InputText
                v-model="query"
                :placeholder="$t('page.search.token.searchPlaceholder')
                  + (state.permissions?.can_list_without_query ? '' : $t('page.search.token.minChars'))"
              />
              <Button type="submit">
                <template #icon>
                  <AppIcon icon-name="search" />
                </template>
              </Button>
            </InputGroup>

            <div class="flex gap-2">
              <Button
                type="button"
                severity="secondary"
                :label="state.activeFamily.title"
                @click="showFamilySwitcher"
              >
                <template #icon>
                  <AppIcon
                    :icon-name="state.activeFamily.icon_hash!"
                    dynamic
                    class="mr-1"
                    size="20px"
                  />
                </template>
              </Button>

              <Button
                type="button"
                severity="warn"
                :label="$t('page.search.token.filters')"
                @click="showCriteriasModal()"
              >
                <template #icon>
                  <AppIcon
                    class="mr-1"
                    icon-name="filter"
                  />
                </template>
              </Button>
            </div>
          </div>
        </form>
      </template>
    </Card>

    <Popover ref="familySwitcher">
      <ViewerFamilySwitcher />
    </Popover>

    <Card
      v-if="currentEntitiesResults"
      class="m-2 p-2"
    >
      <template #header>
        <span class="text-2xl font-bold">
          {{ currentEntitiesResults!.total_results }} {{ resultLabel() }}
        </span>
      </template>

      <template #content>
        <DataView
          :value="currentEntitiesResults!.entities"
          :first="firstRow"
          :rows="pageSize"
          :rows-per-page-options="[5, 10, 20, 50]"
          :total-records="currentEntitiesResults!.total_results"
          data-key="id"
          paginator
          lazy
          layout="list"
          @page="onPage"
        >
          <template #list>
            <ViewerFullResult
              v-for="entity in currentEntitiesResults!.entities"
              :key="`${entity.id}-${researchIncrement}`"
              :entity="entity"
              class="p-col-12"
              @entity-click="selectedCachedEntity"
            />
          </template>
        </DataView>
      </template>
    </Card>
    <ProgressSpinner
      v-if="loading"
      :aria-label="t('page.search.token.loading')"
      class="inset-0 flex items-center justify-center"
    />

    <FullScreenDialog
      v-model:visible="state.hasActiveEntity"
      maximizable
      :style="{ width: '50rem' }"
      :breakpoints="{ '1199px': '75vw', '575px': '90vw' }"
      modal
      dismissable-mask
      @hide="stopEntityLoad"
    >
      <template #header>
        <div class="flex items-center gap-2">
          <CategoryTag :category="state.activeEntity!.category" />
          <h3 class="grow font-bold text-lg m-0">
            {{ state.activeEntity!.entity.display_name }}
          </h3>
        </div>
      </template>

      <ViewerCommentAddForm
        v-if="state.permissions?.can_add_comment && state.activeEntity != null"
        :family="state.activeEntity!.family"
        :entity="state.activeEntity!.entity"
      />
      <ViewerCommonEntityDisplayer
        v-if="state.activeEntity && state.activeEntity.type == 'full'"
        :entity="state.activeEntity!"
        :categories="state.categories"
        @entity-selected="displayEntityId"
      />
      <Skeleton
        v-else
        height="10rem"
        class="mt-4 aspect-video w-full"
      />
    </FullScreenDialog>

    <FullScreenDialog
      v-model:visible="showCriterias"
      maximizable
      :header="$t('page.search.token.filters')"
      :style="{ width: '50rem' }"
      :breakpoints="{ '1199px': '75vw', '575px': '90vw' }"
      modal
    >
      <ViewerFilterConfig
        v-model:filtering-tags="state.filteringTags"
        v-model:filtering-categories="state.filteringCategories"
        v-model:filtering-enums="state.filteringEnums"
      />
    </FullScreenDialog>

    <StartPopup />
  </div>
</template>

<script setup lang="ts">
import type { PageState } from 'primevue/paginator'
import FullScreenDialog from '~/components/viewer/common/FullScreenDialog.vue'
import type { ViewerCachedEntity, ViewerPaginatedCachedEntities } from '~/lib'
import { cancellable } from '~/lib/loading'
import state from '~/lib/viewer-state'

const toast = useToast()
const { t } = useI18n()

// Init state with url token
const route = useRoute()
const token = route.params.token as string
try {
  await state.bootstrapWithToken(token)
  if (!state.permissions?.can_list_entities)
    throw 'Unauthorized'
}
catch {
  toast.add({
    severity: 'error',
    summary: t('page.search.token.error'),
    detail: t('page.search.token.loadDataError'),
    life: 3000,
  })
  if (state.redirectUrl) {
    window.location.href = state.redirectUrl
  }
  else {
    throw createError({
      statusCode: 404,
      statusMessage: 'Page Not Found',
      fatal: true,
    })
  }
}

// Display the given entity if provided in the url query
onMounted(async () => {
  let customStartEntityId: string | undefined = undefined
  if (route.query.ent) {
    if (typeof route.query.ent == 'string') {
      const entityId = route.query.ent
      customStartEntityId = entityId
    }
  }

  if (customStartEntityId) {
    // Custom entity provided, try to display it
    await displayEntityId(customStartEntityId)
    const entity = state.activeEntity?.entity
    const hasEntity = entity?.id == customStartEntityId

    if (hasEntity) {
      // The entity is loaded and its infos are displayed
      // Let's update the filter settings so the UI is consistent

      // Ensure the right family is selected
      state.activeFamily = state.families.find(family => family.id == entity.family_id) || state.activeFamily

      // Ensure the right category is displayed
      state.filteringCategories.forEach((category) => {
        if (category.id == entity.category_id) category.active = true
      })

      // Ensure the right tags are displayed
      state.filteringTags.forEach((tag) => {
        if (state.activeEntity?.tags.filter(({ id }) => id == tag.id)) tag.active = null
      })
    }
  }
})

const query = ref('')
const currentPage = ref(1)
const pageSize = ref(20)
const firstRow = ref(0)

const researchIncrement = ref(0)

const showCriterias = ref(false)

const currentEntitiesResults: Ref<ViewerPaginatedCachedEntities | null> = ref(null)
const familySwitcher = useTemplateRef('familySwitcher')

function resultLabel() {
  const result = currentEntitiesResults!.value?.total_results ?? 0
  return result > 1 ? t('page.search.token.resultsPlural') : t('page.search.token.resultsSingular')
}

async function submitSearch() {
  currentPage.value = 1
  pageSize.value = 20
  firstRow.value = 0
  await refreshResult()
}

function onPage(event: PageState) {
  currentPage.value = event.page + 1
  pageSize.value = event.rows
  firstRow.value = (currentPage.value - 1) * pageSize.value
  refreshResult()
}

const loading = ref(false)
let previousController: AbortController | null = null

async function refreshResult() {
  const currentController = new AbortController()
  try {
    loading.value = true
    if (previousController) previousController.abort()
    previousController = currentController
    currentEntitiesResults.value = null
    researchIncrement.value++
    currentEntitiesResults.value = await state.searchEntities(
      query.value,
      currentPage.value,
      pageSize.value,
      false,
      currentController.signal,
    )
  }
  catch (error) {
    if (error instanceof DOMException && error.name == 'AbortError') {
      // ignore it
    }
    else {
      toast.add({
        severity: 'error',
        summary: t('page.search.token.error'),
        detail: t('page.search.token.loadResultsError'),
        life: 3000,
      })
    }
  }
  finally {
    if (!currentController.signal.aborted) {
      loading.value = false
    }
  }
}

const controller = shallowRef<AbortController | null>(null)

function stopEntityLoad() {
  if (controller.value) {
    controller.value.abort()
  }
}

async function selectedCachedEntity(cacheEntity: ViewerCachedEntity) {
  if (controller.value) controller.value.abort()
  controller.value = new AbortController()
  try {
    await state.selectedCachedEntity(cacheEntity, controller.value.signal)
  }
  catch (e) {
    if (e instanceof DOMException && e.name == 'AbortError') {
      // do nothing
    }
    else {
      toast.add({
        severity: 'error',
        summary: t('page.map.token.error'),
        detail: t('page.map.token.entityLoadError'),
        life: 3000,
      })
    }
  }
}

const selectEntity = cancellable(state, state.selectEntity)

async function displayEntityId(entityId: string) {
  try {
    await selectEntity(entityId)
  }
  catch {
    toast.add({
      severity: 'error',
      summary: t('page.search.token.error'),
      detail: t('page.search.token.loadResultsError'),
      life: 3000,
    })
  }
}

async function showFamilySwitcher(event: Event) {
  familySwitcher.value!.toggle(event)
}

async function showCriteriasModal() {
  showCriterias.value = true
}
</script>

<style>
html:not(.sh-dark) {
  background-color: #f7f7f7;
}

html.sh-dark {
  background-color: #282828;
}
</style>
