package apicache

import (
	"time"

	v1 "k8s.io/api/core/v1"
	metaV1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/watch"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/cache"
)

// return a new cached store for secrets
func newPodStore(client kubernetes.Interface, namespace string, resyncPeriod time.Duration, synced chan struct{}) cache.Store {
	return newListStore(client, storeConfig{
		resource:     "pods",
		namespace:    namespace,
		resyncPeriod: resyncPeriod,
		expectedType: &v1.Pod{},
		listFunc: func(client kubernetes.Interface, namespace string, options metaV1.ListOptions) (runtime.Object, error) {
			return client.CoreV1().Pods(namespace).List(options)
		},
		watchFunc: func(client kubernetes.Interface, namespace string, options metaV1.ListOptions) (watch.Interface, error) {
			return client.CoreV1().Pods(namespace).Watch(options)
		},
	}, synced)
}

// GetPodsFilteredBy returns all pods filtered by a label selector
// e.g. for 'heritage=brigade,component=build,project=%s'
// map[string]string{
//	"heritage":  "brigade",
//	"component": "build",
//	"project":   proj.ID,
// }
func (a *apiCache) GetPodsFilteredBy(selectors map[string]string) ([]v1.Pod, error) {
	var filteredPods []v1.Pod

	if err := a.blockUntilAPICacheSynced(defaultCacheSyncTimeout); err != nil {
		return filteredPods, err
	}

	for _, raw := range a.podStore.List() {

		secret, ok := raw.(*v1.Pod)
		if !ok {
			continue
		}

		// skip if the maps don't match
		if !stringMapsMatch(secret.Labels, selectors) {
			continue
		}

		filteredPods = append(filteredPods, *secret)
	}

	return filteredPods, nil
}
