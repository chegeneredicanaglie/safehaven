<template>
  <div>
    <div class="col-span-12">
      <div
        class="flex flex-col sm:flex-row sm:items-stretch p-6 gap-4"
      >
        <div
          class="md:w-40 flex flex-col"
        >
          <SingleEntityMap
            v-if="props.entity.locations.length > 0"
            :coordinates="locations"
            :fill-color="state.getCategory(props.entity.category_id).fill_color"
            :border-color="state.getCategory(props.entity.category_id).fill_color"
            :icon-hash="state.getCategory(props.entity.category_id).icon_hash"
            :zoom="13"
            :locked="true"
          />
          <div
            v-else
            class="no-geo"
          >
            {{ $t('cmp.viewer.fullResult.noGeo') }}
          </div>
        </div>

        <div class="flex flex-col md:flex-row justify-between md:items-center flex-1 gap-6">
          <div class="flex flex-row md:flex-col justify-between items-start gap-2">
            <div>
              <CategoryTag
                :category="state.getCategory(props.entity.category_id)"
                :size="2"
              />
              <div class="text-lg font-medium mt-2">
                {{ props.entity.display_name }}
              </div>
            </div>
            <div
              v-if="(sortedTags.length) > 0"
              class="flex flex-wrap gap-1"
            >
              <DisplayedTag
                v-for="tag in sortedTags"
                :key="tag.id"
                :tag="tag"
              />
            </div>

            <div
              class="p-1"
              style="border-radius: 30px"
            >
              <ul>
                <li
                  v-for="(loc, idx) in props.entity.locations"
                  :key="idx"
                >
                  {{ loc.plain_text }}
                </li>
              </ul>
            </div>
          </div>

          <div class="flex flex-col md:items-end gap-8">
            <div class="flex flex-row-reverse md:flex-row gap-2">
              <Button
                v-if="state.permissions?.can_access_entity"
                :label="$t('cmp.viewer.fullResult.viewDetails')"
                class="flex-auto md:flex-initial whitespace-nowrap"
                @click="() => $emit('entity-click', props.entity)"
              >
                <template #icon>
                  <AppIcon icon-name="eye" />
                </template>
              </Button>
              <ViewerCommentAddForm
                v-if="state.permissions?.can_add_comment && !state.permissions.can_access_entity"
                :family="state.activeFamily"
                :entity="props.entity"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import type { ViewerSearchedCachedEntity } from '~/lib'
import state from '~/lib/viewer-state'

const props = defineProps<{
  entity: ViewerSearchedCachedEntity
}>()

defineEmits(['entity-click'])

const locations = computed(() => props.entity.locations.map(loc => [loc.x, loc.y]))

const sortedTags = computed(() => {
  return [...props.entity.tags_ids].map(tagId => state.tag(tagId)).filter(tag => tag != undefined).sort((a, b) => a.title.localeCompare(b.title))
})
</script>

<style>
.no-geo {
  text-align: center;
  background-color: #f0f0f0;
  height: 100%;
  width: 100%;
  display: flex;
  justify-content: center;
  align-content: center;
  flex-direction: column;
}
</style>
