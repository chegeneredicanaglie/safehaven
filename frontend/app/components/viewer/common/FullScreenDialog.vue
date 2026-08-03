<template>
  <Drawer
    v-if="isMobile"
    v-model:visible="visible"
    position="full"
    :modal="modal"
    :dismissable="dismissable ?? dismissableMask"
    :show-close-icon="closable"
    block-scroll
    @hide="() => $emit('hide')"
  >
    <template
      v-if="$slots.header"
      #header
    >
      <slot name="header" />
    </template>
    <template
      v-else-if="header"
      #header
    >
      <span class="font-bold text-lg">{{ header }}</span>
    </template>

    <slot />

    <template
      v-if="$slots.footer"
      #footer
    >
      <slot name="footer" />
    </template>
  </Drawer>

  <Dialog
    v-else
    v-model:visible="visible"
    v-bind="$attrs"
    :header="header"
    :modal="modal"
    :closable="closable"
    :dismissable="dismissable"
    :dismissable-mask="dismissableMask"
    @hide="() => $emit('hide')"
  >
    <template
      v-if="$slots.header"
      #header
    >
      <slot name="header" />
    </template>

    <slot />

    <template
      v-if="$slots.footer"
      #footer
    >
      <slot name="footer" />
    </template>
  </Dialog>
</template>

<script setup lang="ts">
import { useMediaQuery } from '@vueuse/core'

const visible = defineModel<boolean>('visible', { required: true })

withDefaults(
  defineProps<{
    header?: string
    modal?: boolean
    closable?: boolean
    dismissable?: boolean
    dismissableMask?: boolean
  }>(),
  { closable: true },
)

defineEmits(['hide'])

const isMobile = useMediaQuery('(max-width: 768px)')
</script>
